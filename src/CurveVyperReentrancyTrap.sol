// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "./ITrap.sol";
import {TrapAlert} from "./TrapTypes.sol";

interface ICurveVyperReentrancyTarget {
    function getMetrics() external view returns (uint256 accountedBalance0, uint256 accountedBalance1, uint256 actualBalance0, uint256 actualBalance1, uint256 virtualPrice, uint256 totalSupply, uint256 blockNumber, bool paused);
}

contract CurveVyperReentrancyTrap is ITrap {
    address public constant TARGET = address(0x0000000000000000000000000000000000001001);
    bytes32 public constant INVARIANT_ID = keccak256("CURVE_ACCOUNTED_BALANCE_MISMATCH");
    uint256 public constant REQUIRED_SAMPLES = 5;

    uint256 internal constant MISMATCH_TOLERANCE = 1_000e18;
    uint256 internal constant VIRTUAL_PRICE_DROP = 1e17;

    struct CollectOutput {
    address target;
    uint256 accountedBalance0;
    uint256 accountedBalance1;
    uint256 actualBalance0;
    uint256 actualBalance1;
    uint256 virtualPrice;
    uint256 totalSupply;
    uint256 blockNumber;
    bool paused;
    }

    function collect() external view returns (bytes memory) {
        if (TARGET.code.length == 0) {
            return abi.encode(CollectOutput({
                target: TARGET,
                accountedBalance0: 1_000_000e18,
            accountedBalance1: 1_000_000e18,
            actualBalance0: 1_000_000e18,
            actualBalance1: 1_000_000e18,
            virtualPrice: 1e18,
            totalSupply: 2_000_000e18,
                blockNumber: block.number,
                paused: false
            }));
        }
        try ICurveVyperReentrancyTarget(TARGET).getMetrics() returns (uint256 accountedBalance0, uint256 accountedBalance1, uint256 actualBalance0, uint256 actualBalance1, uint256 virtualPrice, uint256 totalSupply, uint256 blockNumber, bool paused) {
            return abi.encode(CollectOutput({
                target: TARGET,
                accountedBalance0: accountedBalance0,
                accountedBalance1: accountedBalance1,
                actualBalance0: actualBalance0,
                actualBalance1: actualBalance1,
                virtualPrice: virtualPrice,
                totalSupply: totalSupply,
                blockNumber: blockNumber,
                paused: paused
            }));
        } catch {
            return abi.encode(CollectOutput({
                target: TARGET,
                accountedBalance0: 1_000_000e18,
            accountedBalance1: 1_000_000e18,
            actualBalance0: 1_000_000e18,
            actualBalance1: 1_000_000e18,
            virtualPrice: 1e18,
            totalSupply: 2_000_000e18,
                blockNumber: block.number,
                paused: false
            }));
        }
    }

    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        if (data.length < REQUIRED_SAMPLES) return (false, bytes(""));
        CollectOutput memory latest = abi.decode(data[0], (CollectOutput));
        CollectOutput memory oldest = abi.decode(data[data.length - 1], (CollectOutput));
        if (latest.actualBalance0 + MISMATCH_TOLERANCE < latest.accountedBalance0 || latest.virtualPrice + VIRTUAL_PRICE_DROP < oldest.virtualPrice) {
            TrapAlert memory alert = TrapAlert({
                invariantId: INVARIANT_ID,
                target: latest.target,
                observed: latest.accountedBalance0 - latest.actualBalance0,
                expected: MISMATCH_TOLERANCE,
                blockNumber: latest.blockNumber,
                context: abi.encode(latest.accountedBalance0, latest.accountedBalance1, latest.actualBalance0, latest.actualBalance1, latest.virtualPrice, latest.totalSupply)
            });
            return (true, abi.encode(alert));
        }
        return (false, bytes(""));
    }

}
