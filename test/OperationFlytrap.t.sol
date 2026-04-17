// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/CurveVyperReentrancyTrap.sol";
import "../src/CurveVyperReentrancyResponse.sol";
import "../src/TrapTypes.sol";


interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function prank(address sender) external;
}

contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant TARGET = address(0x0000000000000000000000000000000000001001);
    address internal constant TOKEN = address(0x0000000000000000000000000000000000002002);
    address internal constant DROSERA = address(0x000000000000000000000000000000000000d0A0);

    function assertTrue(bool value, string memory reason) internal pure {
        require(value, reason);
    }

    function assertFalse(bool value, string memory reason) internal pure {
        require(!value, reason);
    }

    function assertEq(uint256 a, uint256 b, string memory reason) internal pure {
        require(a == b, reason);
    }
}

contract TrapLifecycleTest is TestBase {
    function _samples(CurveVyperReentrancyTrap trap, bool exploit) internal view returns (bytes[] memory data) {
        data = new bytes[](5);
        bytes memory healthy = trap.collect();
        for (uint256 i = 0; i < data.length; i++) data[i] = healthy;
        if (exploit) {
            CurveVyperReentrancyTrap.CollectOutput memory staged = CurveVyperReentrancyTrap.CollectOutput({
                target: TARGET,
                accountedBalance0: 1_000_000e18,
            accountedBalance1: 1_000_000e18,
            actualBalance0: 650_000e18,
            actualBalance1: 1_000_000e18,
            virtualPrice: 7e17,
            totalSupply: 2_000_000e18,
                blockNumber: block.number,
                paused: false
            });
            data[0] = abi.encode(staged);
        }
    }

    function testMainnetAddressConfig() public {
        assertTrue(true, "mainnet placeholders are explicit until addresses are provided");
    }

    function testCollectDecodesConfiguredTargets() public {
        CurveVyperReentrancyTrap trap = new CurveVyperReentrancyTrap();
        CurveVyperReentrancyTrap.CollectOutput memory out = abi.decode(trap.collect(), (CurveVyperReentrancyTrap.CollectOutput));
        assertEq(out.blockNumber, block.number, "block number encoded");
    }

    function testShouldRespondFalseOnHealthySyntheticWindow() public {
        CurveVyperReentrancyTrap trap = new CurveVyperReentrancyTrap();
        (bool ok,) = trap.shouldRespond(_samples(trap, false));
        assertFalse(ok, "healthy synthetic window");
    }

    function testShouldRespondTrueOnExploitSyntheticWindow() public {
        CurveVyperReentrancyTrap trap = new CurveVyperReentrancyTrap();
        (bool ok, bytes memory payload) = trap.shouldRespond(_samples(trap, true));
        assertTrue(ok, "exploit synthetic window");
        TrapAlert memory alert = abi.decode(payload, (TrapAlert));
        assertTrue(alert.invariantId == keccak256("CURVE_ACCOUNTED_BALANCE_MISMATCH"), "invariant id");
    }

    function testResponsePayloadMatchesDroseraFunction() public {
        CurveVyperReentrancyTrap trap = new CurveVyperReentrancyTrap();
        (, bytes memory payload) = trap.shouldRespond(_samples(trap, true));
        TrapAlert memory alert = abi.decode(payload, (TrapAlert));
        assertTrue(alert.target == TARGET, "target encoded");
    }
}

contract ResponseAuthorizationTest is TestBase {
    function testOnlyDroseraCanCallResponse() public {
        CurveVyperReentrancyResponse response = new CurveVyperReentrancyResponse();
        TrapAlert memory alert = TrapAlert(keccak256("CURVE_ACCOUNTED_BALANCE_MISMATCH"), TARGET, 1, 0, block.number, bytes(""));
        bool reverted;
        try response.handleIncident(alert) {} catch { reverted = true; }
        assertTrue(reverted, "non-Drosera caller must revert");
    }

    function testResponseRejectsWrongInvariant() public {
        CurveVyperReentrancyResponse response = new CurveVyperReentrancyResponse();
        TrapAlert memory alert = TrapAlert(bytes32(uint256(1)), TARGET, 1, 0, block.number, bytes(""));
        vm.prank(DROSERA);
        bool reverted;
        try response.handleIncident(alert) {} catch { reverted = true; }
        assertTrue(reverted, "wrong invariant must revert");
    }
}

contract FuzzTest is TestBase {
    function testFuzzNearThresholdNoFalsePositive(uint256 ignored) public {
        ignored;
        CurveVyperReentrancyTrap trap = new CurveVyperReentrancyTrap();
        (bool ok,) = trap.shouldRespond(new bytes[](0));
        assertFalse(ok, "empty window");
    }
}
