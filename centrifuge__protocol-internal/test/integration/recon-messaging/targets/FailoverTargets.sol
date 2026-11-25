// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {StandbyTargets} from "./StandbyTargets.sol";

import {PoolId} from "../../../../src/core/types/PoolId.sol";
import {IAdapter} from "../../../../src/core/messaging/interfaces/IAdapter.sol";

import {IAdapterFailover} from "../../../../src/managers/adapters/interfaces/IAdapterFailover.sol";

/// @dev AdapterFailover's lifecycle: the steward arms a set, the timelock runs, anyone executes inside the window
///      that follows, and the steward or the hub can disarm it before then. Time moves only through the fuzzer's
///      block delays (`--max-time-delay`), which reach before, inside and past a `FAILOVER_TIMELOCK` window.
///      Every successful execute is a `setAdapters` on its pool, so it clears that pool's per-session ghosts the
///      way `_install` does.
abstract contract FailoverTargets is StandbyTargets {
    // ─── Hub (envoy) actions ──────────────────────────────────────────────────

    /// @dev FO5 – the steward role is per pool: granting or revoking it on one pool leaves the other untouched.
    function failover_updateSteward(uint8 poolSeed, bool isSteward) public {
        PoolId pool = _failoverPoolAt(poolSeed);
        PoolId other = pool == POOL_A ? POOL_B : POOL_A;
        bool otherBefore = failover.steward(other, address(stewardActor));

        failover.fromHub(pool, abi.encode(uint8(IAdapterFailover.HubCall.UpdateSteward), stewardActor, isSteward));

        t(failover.steward(pool, address(stewardActor)) == isSteward, "FO5: steward getter does not reflect update");
        t(failover.steward(other, address(stewardActor)) == otherBefore, "FO5: steward update leaked to another pool");
    }

    /// @dev FO4 – the hub's veto disarms whatever is pending, whoever armed it and however close it is to the
    ///      window.
    function failover_hubVeto(uint8 poolSeed) public {
        PoolId pool = _failoverPoolAt(poolSeed);

        failover.fromHub(pool, abi.encode(uint8(IAdapterFailover.HubCall.CancelFailover), REMOTE_CENTRIFUGE_ID));
        _recordFailoverCleared(pool);

        (uint64 executableAt, bytes32 paramsHash) = failover.pendingFailover(REMOTE_CENTRIFUGE_ID, pool);
        t(executableAt == 0 && paramsHash == bytes32(0), "FO4: a hub veto left the failover armed");
    }

    /// @dev Enables or disables failover for a pool on the MultiAdapter side. Without the role an execute
    ///      cannot install (FO10), which is how a pool opts out.
    function failover_updateManager(uint8 poolSeed, bool canManage) public {
        PoolId pool = _failoverPoolAt(poolSeed);
        multiAdapter.updateManager(pool, address(failover), canManage);
        t(multiAdapter.manager(pool, address(failover)) == canManage, "failover role: manager getter mismatch");
    }

    // ─── Steward actions ──────────────────────────────────────────────────────

    /// @dev FO3 – arming records the exact set behind `now + timelock`, overwriting any earlier proposal.
    function failover_initiate(uint8 poolSeed, uint8 setSeed, uint8 thresholdSeed) public {
        PoolId pool = _failoverPoolAt(poolSeed);
        precondition(failover.steward(pool, address(stewardActor)));
        IAdapter[] memory adapters = _failoverSet(setSeed);
        uint8 threshold_ = uint8(between(uint256(thresholdSeed), 1, adapters.length));

        stewardActor.initiate(REMOTE_CENTRIFUGE_ID, pool, adapters, threshold_);
        uint64 expectedAt = uint64(block.timestamp) + FAILOVER_TIMELOCK;
        _recordFailoverArmed(pool, adapters, threshold_, expectedAt);

        (uint64 executableAt, bytes32 paramsHash) = failover.pendingFailover(REMOTE_CENTRIFUGE_ID, pool);
        eq(executableAt, expectedAt, "FO3: armed with the wrong executableAt");
        t(paramsHash == keccak256(abi.encode(adapters, threshold_)), "FO3: armed with the wrong params hash");
    }

    /// @dev FO4 – the steward can withdraw its own proposal.
    function failover_stewardCancel(uint8 poolSeed) public {
        PoolId pool = _failoverPoolAt(poolSeed);
        precondition(failover.steward(pool, address(stewardActor)));

        stewardActor.cancel(REMOTE_CENTRIFUGE_ID, pool);
        _recordFailoverCleared(pool);

        (uint64 executableAt, bytes32 paramsHash) = failover.pendingFailover(REMOTE_CENTRIFUGE_ID, pool);
        t(executableAt == 0 && paramsHash == bytes32(0), "FO4: a steward cancel left the failover armed");
    }

    // ─── Permissionless execute ───────────────────────────────────────────────

    /// @dev FO2 – liveness and exactness, the reason the contract exists: a proposal armed and not disarmed, inside
    ///      its window, on a pool that opted in, ALWAYS installs, whatever reconfigured, blocked or voted on the
    ///      pool meanwhile. It installs exactly the armed set and threshold as the pool's next session and is
    ///      consumed, so it cannot install twice.
    function failover_execute(uint8 poolSeed) public {
        PoolId pool = _failoverPoolAt(poolSeed);
        precondition(_failoverInWindow(pool));
        precondition(multiAdapter.manager(pool, address(failover)));
        IAdapter[] memory adapters = ghost_failoverAdapters[pool];
        uint8 threshold_ = ghost_failoverThreshold[pool];
        uint16 sidBefore = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, pool);

        try failover.executeFailover(REMOTE_CENTRIFUGE_ID, pool, adapters, threshold_) {}
        catch {
            t(false, "FO2: an armed failover inside its window did not execute");
        }
        _recordFailoverCleared(pool);
        _clearTrackedDeliveries(pool);

        eq(multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, pool), sidBefore + 1, "FO2: not the next session");
        IAdapter[] memory list = _activeList(pool);
        eq(list.length, adapters.length, "FO2: installed set size differs from the armed one");
        for (uint256 i; i < list.length; i++) {
            t(address(list[i]) == address(adapters[i]), "FO2: installed set differs from the armed one");
        }
        eq(multiAdapter.threshold(REMOTE_CENTRIFUGE_ID, pool), threshold_, "FO2: installed threshold differs");
        (uint64 executableAt,) = failover.pendingFailover(REMOTE_CENTRIFUGE_ID, pool);
        eq(executableAt, 0, "FO2: an executed failover is still armed");
    }

    // ─── Negatives ────────────────────────────────────────────────────────────

    /// @dev FO6 – nothing installs before the veto window has run its course.
    function failover_execute_early_mustRevert(uint8 poolSeed) public {
        PoolId pool = _failoverPoolAt(poolSeed);
        uint64 at = ghost_failoverExecutableAt[pool];
        precondition(at != 0 && block.timestamp < at);

        try failover.executeFailover(
            REMOTE_CENTRIFUGE_ID, pool, ghost_failoverAdapters[pool], ghost_failoverThreshold[pool]
        ) {
            t(false, "FO6: executed before the timelock elapsed");
        } catch (bytes memory err) {
            t(checkError(err, "TimelockNotElapsed()"), "FO6: wrong revert (expected TimelockNotElapsed)");
        }
        require(false);
    }

    /// @dev FO7 – a proposal left unexecuted for a full timelock past its window lapses: a stale arming cannot be
    ///      held back and fired later.
    function failover_execute_expired_mustRevert(uint8 poolSeed) public {
        PoolId pool = _failoverPoolAt(poolSeed);
        uint64 at = ghost_failoverExecutableAt[pool];
        precondition(at != 0 && block.timestamp > at + FAILOVER_TIMELOCK);

        try failover.executeFailover(
            REMOTE_CENTRIFUGE_ID, pool, ghost_failoverAdapters[pool], ghost_failoverThreshold[pool]
        ) {
            t(false, "FO7: executed an expired failover");
        } catch (bytes memory err) {
            t(checkError(err, "FailoverExpired()"), "FO7: wrong revert (expected FailoverExpired)");
        }
        require(false);
    }

    /// @dev FO8 – with nothing armed for (centrifugeId, pool) no set installs: never armed, cancelled, vetoed and
    ///      already executed all look the same. Any chain and any pool, the global one included.
    function failover_execute_unarmed_mustRevert(uint16 centrifugeId, uint8 poolSeed, uint8 setSeed) public {
        PoolId pool = _poolAt(poolSeed);
        precondition(!_failoverArmed(centrifugeId, pool));
        IAdapter[] memory adapters = _failoverSet(setSeed);

        try failover.executeFailover(centrifugeId, pool, adapters, 1) {
            t(false, "FO8: executed a failover that was never armed or was disarmed");
        } catch (bytes memory err) {
            t(checkError(err, "NoPendingFailover()"), "FO8: wrong revert (expected NoPendingFailover)");
        }
        require(false);
    }

    /// @dev FO9 – the executor cannot substitute a set: inside the window, anything but the armed params fails.
    function failover_execute_wrongParams_mustRevert(uint8 poolSeed, uint8 setSeed, uint8 threshold_) public {
        PoolId pool = _failoverPoolAt(poolSeed);
        precondition(_failoverInWindow(pool));
        IAdapter[] memory adapters = _failoverSet(setSeed);
        precondition(keccak256(abi.encode(adapters, threshold_)) != _failoverParamsHash(pool));

        try failover.executeFailover(REMOTE_CENTRIFUGE_ID, pool, adapters, threshold_) {
            t(false, "FO9: executed a set other than the armed one");
        } catch (bytes memory err) {
            t(checkError(err, "ParamsMismatch()"), "FO9: wrong revert (expected ParamsMismatch)");
        }
        require(false);
    }

    /// @dev FO10 – a pool that has not given the failover the MultiAdapter manager role cannot be taken over.
    function failover_execute_noRole_mustRevert(uint8 poolSeed) public {
        PoolId pool = _failoverPoolAt(poolSeed);
        precondition(_failoverInWindow(pool));
        precondition(!multiAdapter.manager(pool, address(failover)));

        try failover.executeFailover(
            REMOTE_CENTRIFUGE_ID, pool, ghost_failoverAdapters[pool], ghost_failoverThreshold[pool]
        ) {
            t(false, "FO10: installed on a pool without the failover role");
        } catch (bytes memory err) {
            t(checkError(err, "NotAuthorized()"), "FO10: wrong revert (expected NotAuthorized)");
        }
        require(false);
    }

    /// @dev FO11 – only the pool's steward arms or cancels, and a steward of one pool is nobody on another.
    function failover_notSteward_mustRevert(uint8 poolSeed, bool cancel) public {
        PoolId pool = _poolAt(poolSeed);
        precondition(!failover.steward(pool, address(stewardActor)));
        IAdapter[] memory adapters = _failoverSet(0);

        if (cancel) {
            try stewardActor.cancel(REMOTE_CENTRIFUGE_ID, pool) {
                t(false, "FO11: a non-steward cancelled a failover");
            } catch (bytes memory err) {
                t(checkError(err, "NotSteward()"), "FO11: wrong revert on cancel (expected NotSteward)");
            }
        } else {
            try stewardActor.initiate(REMOTE_CENTRIFUGE_ID, pool, adapters, 1) {
                t(false, "FO11: a non-steward armed a failover");
            } catch (bytes memory err) {
                t(checkError(err, "NotSteward()"), "FO11: wrong revert on initiate (expected NotSteward)");
            }
        }
        require(false);
    }

    /// @dev FO12 – a zero threshold is refused at arming, not only at install.
    function failover_initiate_zeroThreshold_mustRevert(uint8 poolSeed, uint8 setSeed) public {
        PoolId pool = _failoverPoolAt(poolSeed);
        precondition(failover.steward(pool, address(stewardActor)));
        IAdapter[] memory adapters = _failoverSet(setSeed);

        try stewardActor.initiate(REMOTE_CENTRIFUGE_ID, pool, adapters, 0) {
            t(false, "FO12: armed a failover with a zero threshold");
        } catch (bytes memory err) {
            t(checkError(err, "InvalidThreshold()"), "FO12: wrong revert (expected InvalidThreshold)");
        }
        require(false);
    }

    /// @dev FO13 – only the envoy speaks for the hub: anyone else could veto every failover or appoint a steward.
    function failover_fromHub_notEnvoy_mustRevert(uint8 poolSeed, bool veto) public {
        PoolId pool = _poolAt(poolSeed);
        bytes memory payload = veto
            ? abi.encode(uint8(IAdapterFailover.HubCall.CancelFailover), REMOTE_CENTRIFUGE_ID)
            : abi.encode(uint8(IAdapterFailover.HubCall.UpdateSteward), stewardActor, true);

        try stewardActor.fromHub(pool, payload) {
            t(false, "FO13: a non-envoy called fromHub");
        } catch (bytes memory err) {
            t(checkError(err, "NotEnvoy()"), "FO13: wrong revert (expected NotEnvoy)");
        }
        require(false);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _failoverInWindow(PoolId pool) internal view returns (bool) {
        uint64 at = ghost_failoverExecutableAt[pool];
        return at != 0 && block.timestamp >= at && block.timestamp <= at + FAILOVER_TIMELOCK;
    }

    /// @dev A non-empty subset of the four adapters, in a fixed order; the standby is one of them, so a failover
    ///      can install a set that relies on it.
    function _failoverSet(uint8 setSeed) internal view returns (IAdapter[] memory adapters) {
        uint8 mask = setSeed % 15 + 1;
        address[4] memory candidates = [address(adapter0), address(adapter1), address(adapter2), address(standby)];
        adapters = new IAdapter[](_popCount(mask));
        uint256 k;
        for (uint256 i; i < 4; i++) {
            if (mask & (1 << i) != 0) adapters[k++] = IAdapter(candidates[i]);
        }
    }

    function _popCount(uint8 mask) internal pure returns (uint256 n) {
        for (; mask != 0; mask >>= 1) {
            n += mask & 1;
        }
    }
}
