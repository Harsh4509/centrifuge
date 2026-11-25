// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Setup} from "./Setup.sol";

import {PoolId} from "../../../src/core/types/PoolId.sol";
import {IAdapter} from "../../../src/core/messaging/interfaces/IAdapter.sol";

import {Utils} from "@recon/Utils.sol";
import {Asserts} from "@chimera/Asserts.sol";

struct TrackedPair {
    uint16 centrifugeId;
    bytes32 payloadHash;
}

/// @dev A per-session entry: `poolId` is the pool whose adapter set carried the deliveries (the routed
///      pool), `messagePoolId` the pool the message names. They differ only for a fallback payload.
struct SessionPair {
    uint16 centrifugeId;
    PoolId poolId;
    PoolId messagePoolId;
    bytes32 payloadHash;
}

/// @dev `Utils` is inherited here, not per-target, so `checkError` is available suite-wide.
abstract contract BeforeAfter is Setup, Utils, Asserts {
    // ─── Per-session ghosts (reset when the routed pool reconfigures) ─────────
    // Used by M1, M4, G2, G4: bounds within the current session of the routed pool only. Keyed by the
    // routed pool, since each pool has its own sessions, threshold and vote tally.

    mapping(uint16 centrifugeId => mapping(PoolId => mapping(bytes32 payloadHash => uint256))) internal
        ghost_deliveries;

    SessionPair[] internal ghost_tracked;
    mapping(uint16 centrifugeId => mapping(PoolId => mapping(bytes32 payloadHash => bool))) internal ghost_isTracked;

    /// @dev `countingProcessor.callCount` before the session's first delivery; properties read the delta.
    mapping(uint16 centrifugeId => mapping(PoolId => mapping(bytes32 payloadHash => uint256))) internal
        ghost_baselineCallCount;

    /// @dev Same idea for `gateway.failedMessages`.
    mapping(uint16 centrifugeId => mapping(PoolId => mapping(bytes32 payloadHash => uint256))) internal
        ghost_baselineFailedMessages;

    /// @dev Vote-tally key `keccak256(routedPoolId ++ sessionId ++ payload)`, captured at first track.
    ///      `multiAdapter.votes` is keyed by this; callCount / failedMessages by the unwrapped hash.
    mapping(uint16 centrifugeId => mapping(PoolId => mapping(bytes32 payloadHash => bytes32))) internal ghost_voteKey;

    // ─── Cumulative (cross-session) ghosts (NEVER reset) ──────────────────────
    // Used by M1c (weighted-execution ledger), callCount monotonicity, alex1 replay detection.

    /// @dev Total deliveries across ALL sessions per (cId, hash).
    mapping(uint16 centrifugeId => mapping(bytes32 payloadHash => uint256)) internal ghost_cumDeliveries;

    /// @dev Sum over observed executions of (delta_callCount * threshold_at_observation); bounded by M1c.
    mapping(uint16 centrifugeId => mapping(bytes32 payloadHash => uint256)) internal ghost_cumExecutionsWeighted;

    /// @dev Last observed `callCount(cId, hash)`: detects new executions and backs the monotonicity property.
    mapping(uint16 centrifugeId => mapping(bytes32 payloadHash => uint256)) internal ghost_cumLastSeenCallCount;

    /// @dev Last observed `failedMessages(cId, hash)`, so `_recordQuorumEvent` also detects failed executions.
    mapping(uint16 centrifugeId => mapping(bytes32 payloadHash => uint256)) internal ghost_cumLastSeenFailedMessages;

    /// @dev Cross-session tracked pairs; entries are NEVER removed, so cumulative properties see every pair.
    TrackedPair[] internal ghost_cumTracked;
    mapping(uint16 centrifugeId => mapping(bytes32 payloadHash => bool)) internal ghost_isCumTracked;

    /// @dev Outstanding unpaid batches per (cId, batchHash) as the HARNESS believes them: +1 on a retained
    ///      send, -1 on a settled repay. Deliberately in the cumulative layer, NOT the per-session one:
    ///      `Gateway.underpaid` is keyed by (cId, batchHash) with no session component, so a retained batch
    ///      outlives a reconfigure and clearing this on reconfigure would desync U6 against live state.
    mapping(uint16 centrifugeId => mapping(bytes32 batchHash => uint256)) internal ghost_underpaidOutstanding;

    TrackedPair[] internal ghost_underpaidTracked;
    mapping(uint16 centrifugeId => mapping(bytes32 batchHash => bool)) internal ghost_isUnderpaidTracked;

    /// @dev Standby credits as the HARNESS believes them, per credit id: +1 for every dispatch that included the
    ///      standby, +1 forwarded per successful `forward`. Cumulative: a credit is keyed on the session-wrapped
    ///      payload, so a reconfigure strands it rather than clearing it.
    mapping(bytes32 id => uint256) internal ghost_standbySent;
    mapping(bytes32 id => uint256) internal ghost_standbyForwarded;
    bytes[] internal ghost_standbyPayloads;
    mapping(bytes32 id => bool) internal ghost_isStandbyTracked;

    // ─── AdapterFailover ledger ───────────────────────────────────────────────
    // The proposal the HARNESS believes is armed per failover pool, on REMOTE_CENTRIFUGE_ID (no handler arms
    // another chain). Written on initiate, cleared on cancel, veto and execute; FO1 compares it to the contract.

    mapping(PoolId => uint64) internal ghost_failoverExecutableAt;
    mapping(PoolId => IAdapter[]) internal ghost_failoverAdapters;
    mapping(PoolId => uint8) internal ghost_failoverThreshold;

    // Deliberately NO ghost mirroring the active adapter set: targets read the live `_activeList()` /
    // `_isActive()`. A "first N of adapter0..2" count ghost misreads non-prefix sets like [adapter1].

    // ─── Delivery accounting helpers ──────────────────────────────────────────

    /// @dev PRE-deliver hook: baseline before the on-chain effect, so this delivery's executions show as delta.
    function _captureBaselines(uint16 centrifugeId, bytes memory payload) internal {
        bytes32 payloadHash = keccak256(payload);
        PoolId pool = _route(payload);

        if (!ghost_isTracked[centrifugeId][pool][payloadHash]) {
            ghost_isTracked[centrifugeId][pool][payloadHash] = true;
            ghost_tracked.push(SessionPair(centrifugeId, pool, countingProcessor.messagePoolId(payload), payloadHash));
            ghost_baselineCallCount[centrifugeId][pool][payloadHash] =
                countingProcessor.callCount(centrifugeId, payloadHash);
            ghost_baselineFailedMessages[centrifugeId][pool][payloadHash] =
                gateway.failedMessages(centrifugeId, payloadHash);
            ghost_voteKey[centrifugeId][pool][payloadHash] = _voteKey(pool, _wrapAt(pool, payload));
        }

        if (!ghost_isCumTracked[centrifugeId][payloadHash]) {
            ghost_isCumTracked[centrifugeId][payloadHash] = true;
            ghost_cumTracked.push(TrackedPair(centrifugeId, payloadHash));
            ghost_cumLastSeenCallCount[centrifugeId][payloadHash] =
                countingProcessor.callCount(centrifugeId, payloadHash);
            ghost_cumLastSeenFailedMessages[centrifugeId][payloadHash] =
                gateway.failedMessages(centrifugeId, payloadHash);
        }
    }

    /// @dev POST-deliver hook, success path ONLY: callers must skip it on revert so reverts don't pollute ghosts.
    ///      A delivery is anything that casts one vote: handle() or vote().
    function _recordSuccessfulDelivery(uint16 centrifugeId, bytes memory payload) internal {
        bytes32 payloadHash = keccak256(payload);
        PoolId pool = _route(payload);

        ghost_deliveries[centrifugeId][pool][payloadHash]++;
        ghost_cumDeliveries[centrifugeId][payloadHash]++;

        _recordQuorumEvent(centrifugeId, pool, payloadHash);
    }

    /// @dev Credit every QUORUM EVENT caused by the just-completed handler to the cumulative weighted ledger at
    ///      the current threshold. A quorum event consumes a full `threshold` of fresh votes: a successful
    ///      execution (callCount up) or a failed one (failedMessages up). retry / clearFailedMessage cast no fresh
    ///      votes, so they call `_syncCumCounters` and credit nothing; execute() is credited without a delivery.
    ///      The threshold is the routed pool's: that is the set whose votes the event consumed.
    function _recordQuorumEvent(uint16 centrifugeId, PoolId routedPool, bytes32 payloadHash) internal {
        uint256 currentCallCount = countingProcessor.callCount(centrifugeId, payloadHash);
        uint256 currentFailed = gateway.failedMessages(centrifugeId, payloadHash);

        uint256 lastCallCount = ghost_cumLastSeenCallCount[centrifugeId][payloadHash];
        uint256 lastFailed = ghost_cumLastSeenFailedMessages[centrifugeId][payloadHash];

        uint256 execEvents = currentCallCount > lastCallCount ? currentCallCount - lastCallCount : 0;
        uint256 failEvents = currentFailed > lastFailed ? currentFailed - lastFailed : 0;
        uint256 events = execEvents + failEvents;

        if (events > 0) {
            uint256 thresholdNow = uint256(multiAdapter.threshold(REMOTE_CENTRIFUGE_ID, routedPool));
            ghost_cumExecutionsWeighted[centrifugeId][payloadHash] += events * thresholdNow;
        }

        ghost_cumLastSeenCallCount[centrifugeId][payloadHash] = currentCallCount;
        ghost_cumLastSeenFailedMessages[centrifugeId][payloadHash] = currentFailed;
    }

    /// @dev Advance the last-seen counters WITHOUT crediting the weighted ledger: retry / clearFailedMessage cast
    ///      no fresh votes, so their movements must be absorbed here or a later quorum event is mis-detected.
    function _syncCumCounters(uint16 centrifugeId, bytes32 payloadHash) internal {
        ghost_cumLastSeenCallCount[centrifugeId][payloadHash] = countingProcessor.callCount(centrifugeId, payloadHash);
        ghost_cumLastSeenFailedMessages[centrifugeId][payloadHash] = gateway.failedMessages(centrifugeId, payloadHash);
    }

    // ─── Standby credit ledger helpers ───────────────────────────────────────

    /// @dev A dispatch of `wrapped` went to every adapter in `list`; credit the standby if it was one of them.
    function _recordStandbySend(IAdapter[] memory list, bytes memory wrapped) internal {
        for (uint256 i; i < list.length; i++) {
            if (address(list[i]) != address(standby)) continue;
            bytes32 id = _standbyId(wrapped);
            if (!ghost_isStandbyTracked[id]) {
                ghost_isStandbyTracked[id] = true;
                ghost_standbyPayloads.push(wrapped);
            }
            ghost_standbySent[id]++;
        }
    }

    // ─── AdapterFailover ledger helpers ───────────────────────────────────────

    function _recordFailoverArmed(PoolId pool, IAdapter[] memory adapters, uint8 threshold_, uint64 executableAt)
        internal
    {
        ghost_failoverExecutableAt[pool] = executableAt;
        ghost_failoverAdapters[pool] = adapters;
        ghost_failoverThreshold[pool] = threshold_;
    }

    function _recordFailoverCleared(PoolId pool) internal {
        delete ghost_failoverExecutableAt[pool];
        delete ghost_failoverAdapters[pool];
        delete ghost_failoverThreshold[pool];
    }

    function _failoverArmed(uint16 centrifugeId, PoolId pool) internal view returns (bool) {
        return centrifugeId == REMOTE_CENTRIFUGE_ID && ghost_failoverExecutableAt[pool] != 0;
    }

    function _failoverParamsHash(PoolId pool) internal view returns (bytes32) {
        IAdapter[] memory adapters = ghost_failoverAdapters[pool];
        return keccak256(abi.encode(adapters, ghost_failoverThreshold[pool]));
    }

    // ─── Underpaid-batch ledger helpers ───────────────────────────────────────

    /// @dev A send was retained instead of dispatched, so one instance is now outstanding.
    function _recordUnderpaidRetained(uint16 centrifugeId, bytes32 batchHash) internal {
        if (!ghost_isUnderpaidTracked[centrifugeId][batchHash]) {
            ghost_isUnderpaidTracked[centrifugeId][batchHash] = true;
            ghost_underpaidTracked.push(TrackedPair(centrifugeId, batchHash));
        }
        ghost_underpaidOutstanding[centrifugeId][batchHash]++;
    }

    /// @dev A repay settled one instance. A revert here would be discarded like any handler revert, and U6 only
    ///      walks the batches the ledger recorded, so a settled batch it never recorded is reported by `t`.
    function _recordUnderpaidSettled(uint16 centrifugeId, bytes32 batchHash) internal {
        t(ghost_underpaidOutstanding[centrifugeId][batchHash] > 0, "U6b: settled a batch the ledger never recorded");
        if (ghost_underpaidOutstanding[centrifugeId][batchHash] > 0) {
            ghost_underpaidOutstanding[centrifugeId][batchHash]--;
        }
    }

    /// @dev Reset PER-SESSION ghosts after `setAdapters` on `pool`, so M1/M4/G2/G4 scope to one session. Drops
    ///      the pool's own entries, and the entries of messages naming `pool` that the global set carried
    ///      while it was unconfigured: their route has just moved, so the global entry would otherwise keep
    ///      counting executions that now consume the pool's votes. Other pools' sessions are untouched.
    function _clearTrackedDeliveries(PoolId pool) internal {
        for (uint256 i; i < ghost_tracked.length;) {
            SessionPair memory p = ghost_tracked[i];
            if (!(p.poolId == pool) && !(p.messagePoolId == pool)) {
                i++;
                continue;
            }
            delete ghost_deliveries[p.centrifugeId][p.poolId][p.payloadHash];
            delete ghost_isTracked[p.centrifugeId][p.poolId][p.payloadHash];
            delete ghost_baselineCallCount[p.centrifugeId][p.poolId][p.payloadHash];
            delete ghost_baselineFailedMessages[p.centrifugeId][p.poolId][p.payloadHash];
            delete ghost_voteKey[p.centrifugeId][p.poolId][p.payloadHash];
            ghost_tracked[i] = ghost_tracked[ghost_tracked.length - 1];
            ghost_tracked.pop();
        }
    }
}
