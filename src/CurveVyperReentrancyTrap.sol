// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "./ITrap.sol";
import {TrapAlert} from "./TrapTypes.sol";

interface ICurveVyperReentrancyEnvironmentRegistryView {
    function environmentId() external view returns (bytes32);
    function monitoredTarget() external view returns (address);
    function active() external view returns (bool);
}

interface ICurveVyperReentrancyTarget {
    function getMetrics() external view returns (uint256 accountedBalance0, uint256 accountedBalance1, uint256 actualBalance0, uint256 actualBalance1, uint256 virtualPrice, uint256 totalSupply, uint256 observedBlockNumber, bool paused);
}

contract CurveVyperReentrancyTrap is ITrap {
    address public constant REGISTRY = address(0x0000000000000000000000000000000000003001);
    bytes32 public constant INVARIANT_ID = keccak256("CURVE_ACCOUNTED_BALANCE_MISMATCH_V2");
    uint256 public constant REQUIRED_SAMPLES = 5;
    uint8 internal constant STATUS_OK = 0;
    uint8 internal constant STATUS_REGISTRY_INACTIVE = 1;
    uint8 internal constant STATUS_TARGET_MISSING = 2;
    uint8 internal constant STATUS_METRICS_CALL_FAILED = 3;
    uint8 internal constant STATUS_INVALID_METRICS = 4;
    uint256 internal constant BREACH_WINDOW = 5;
    uint256 internal constant MIN_BREACH_COUNT = 2;
    uint256 internal constant MISMATCH_TOLERANCE = 1_000e18;
    uint256 internal constant VIRTUAL_PRICE_DROP = 1e17;

    struct CollectOutput {
        bytes32 environmentId;
        address registry;
        address target;
        uint8 status;
        uint256 accountedBalance0;
        uint256 accountedBalance1;
        uint256 actualBalance0;
        uint256 actualBalance1;
        uint256 virtualPrice;
        uint256 totalSupply;
        uint256 observedBlockNumber;
        bool paused;
    }

    function collect() external view returns (bytes memory) {
        if (REGISTRY.code.length == 0) {
            return _status(bytes32(0), address(0), STATUS_REGISTRY_INACTIVE);
        }

        ICurveVyperReentrancyEnvironmentRegistryView registry = ICurveVyperReentrancyEnvironmentRegistryView(REGISTRY);
        bytes32 environmentId = registry.environmentId();
        address target = registry.monitoredTarget();
        if (!registry.active()) return _status(environmentId, target, STATUS_REGISTRY_INACTIVE);
        if (target.code.length == 0) return _status(environmentId, target, STATUS_TARGET_MISSING);

        try ICurveVyperReentrancyTarget(target).getMetrics() returns (uint256 accountedBalance0, uint256 accountedBalance1, uint256 actualBalance0, uint256 actualBalance1, uint256 virtualPrice, uint256 totalSupply, uint256 observedBlockNumber, bool paused) {
            if (observedBlockNumber == 0 || paused) {
                return abi.encode(CollectOutput({
                    environmentId: environmentId,
                    registry: REGISTRY,
                    target: target,
                    status: paused ? STATUS_OK : STATUS_INVALID_METRICS,
                    accountedBalance0: accountedBalance0,
                    accountedBalance1: accountedBalance1,
                    actualBalance0: actualBalance0,
                    actualBalance1: actualBalance1,
                    virtualPrice: virtualPrice,
                    totalSupply: totalSupply,
                    observedBlockNumber: observedBlockNumber == 0 ? block.number : observedBlockNumber,
                    paused: paused
                }));
            }
            return abi.encode(CollectOutput({
                environmentId: environmentId,
                registry: REGISTRY,
                target: target,
                status: STATUS_OK,
                accountedBalance0: accountedBalance0,
                    accountedBalance1: accountedBalance1,
                    actualBalance0: actualBalance0,
                    actualBalance1: actualBalance1,
                    virtualPrice: virtualPrice,
                    totalSupply: totalSupply,
                observedBlockNumber: observedBlockNumber,
                paused: paused
            }));
        } catch {
            return _status(environmentId, target, STATUS_METRICS_CALL_FAILED);
        }
    }

    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        if (data.length < REQUIRED_SAMPLES) return (false, bytes(""));
        CollectOutput memory latest = abi.decode(data[0], (CollectOutput));
        CollectOutput memory historical = abi.decode(data[data.length - 1], (CollectOutput));
        if (latest.status != STATUS_OK || latest.paused) return (false, bytes(""));
        if (historical.status != STATUS_OK || historical.environmentId != latest.environmentId || historical.target != latest.target) {
            return (false, bytes(""));
        }

        bool latestBreached = (latest.actualBalance0 + MISMATCH_TOLERANCE < latest.accountedBalance0 || latest.virtualPrice + VIRTUAL_PRICE_DROP < historical.virtualPrice);
        if (!latestBreached) return (false, bytes(""));

        uint256 checked = data.length < BREACH_WINDOW ? data.length : BREACH_WINDOW;
        uint256 breachCount;
        for (uint256 i = 0; i < checked; i++) {
            CollectOutput memory sample = abi.decode(data[i], (CollectOutput));
            if (sample.status != STATUS_OK || sample.paused || sample.target != latest.target) continue;
            if (sample.observedBlockNumber >= historical.observedBlockNumber) {
                if (sample.actualBalance0 + MISMATCH_TOLERANCE < sample.accountedBalance0 || sample.virtualPrice + VIRTUAL_PRICE_DROP < historical.virtualPrice) breachCount++;
            }
        }

        uint256 deteriorationSignals;
        if (latest.observedBlockNumber >= historical.observedBlockNumber) deteriorationSignals++;
        if (latest.target == historical.target) deteriorationSignals++;

        if (breachCount < MIN_BREACH_COUNT || deteriorationSignals < 2) return (false, bytes(""));

        TrapAlert memory alert = TrapAlert({
            invariantId: INVARIANT_ID,
            target: latest.target,
            observed: latest.accountedBalance0 - latest.actualBalance0,
            expected: MISMATCH_TOLERANCE,
            blockNumber: latest.observedBlockNumber,
            environmentId: latest.environmentId,
            context: abi.encode(latest.registry, latest.status, latest.accountedBalance0, latest.accountedBalance1, latest.actualBalance0, latest.actualBalance1, latest.virtualPrice, latest.totalSupply, breachCount, deteriorationSignals)
        });
        return (true, abi.encode(alert));
    }

    function _status(bytes32 environmentId, address target, uint8 status) internal view returns (bytes memory) {
        return abi.encode(CollectOutput({
            environmentId: environmentId,
            registry: REGISTRY,
            target: target,
            status: status,
            accountedBalance0: 1_000_000e18,
                    accountedBalance1: 1_000_000e18,
                    actualBalance0: 1_000_000e18,
                    actualBalance1: 1_000_000e18,
                    virtualPrice: 1e18,
                    totalSupply: 2_000_000e18,
            observedBlockNumber: block.number,
            paused: false
        }));
    }

}
