// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {PoolId} from "../../../../src/core/types/PoolId.sol";
import {IAdapter} from "../../../../src/core/messaging/interfaces/IAdapter.sol";
import {MAX_ADAPTER_COUNT} from "../../../../src/core/messaging/interfaces/IMultiAdapter.sol";

import {BeforeAfter, TrackedPair, SessionPair} from "../BeforeAfter.sol";

abstract contract MessagingProperties is BeforeAfter {
    // ─── MultiAdapter invariants ──────────────────────────────────────────────

    /// @dev M1 – Per session, per (centrifugeId, routed pool, payloadHash): callCount * threshold <= deliveries,
    ///      at the routed pool's threshold. Counted from the first-delivery baseline; `_clearTrackedDeliveries`
    ///      resets the pool's entries on its reconfigure. Across pools this is also the vote-namespacing
    ///      check: a tally shared between two pools lets one pool's votes execute under the other with fewer
    ///      of its own deliveries than its threshold.
    function property_M1_threshold_respected() public {
        uint256 n = ghost_tracked.length;

        for (uint256 i; i < n; i++) {
            SessionPair memory p = ghost_tracked[i];
            uint256 threshold_ = uint256(multiAdapter.threshold(p.centrifugeId, p.poolId));

            uint256 deliveries = ghost_deliveries[p.centrifugeId][p.poolId][p.payloadHash];
            uint256 calls = countingProcessor.callCount(p.centrifugeId, p.payloadHash)
                - ghost_baselineCallCount[p.centrifugeId][p.poolId][p.payloadHash];

            lte(calls * threshold_, deliveries, "M1: callCount * threshold > deliveries");
        }
    }

    /// @dev M2 – In every pool, every index in the active set [0, quorum) is non-zero and pairwise distinct.
    function property_M2_adapter_set_integrity() public {
        for (uint8 k; k < POOL_COUNT; k++) {
            PoolId pool = _poolAt(k);
            uint8 q = multiAdapter.quorum(REMOTE_CENTRIFUGE_ID, pool);
            if (q == 0) continue;

            uint16 sid = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, pool);
            IAdapter[] memory active = new IAdapter[](q);
            for (uint8 i; i < q; i++) {
                active[i] = multiAdapter.adapters(REMOTE_CENTRIFUGE_ID, pool, sid, i);
                t(address(active[i]) != address(0), "M2: adapter at active index is zero");
            }

            for (uint8 i; i < q; i++) {
                for (uint8 j = i + 1; j < q; j++) {
                    t(active[i] != active[j], "M2: duplicate adapters in active set");
                }
            }
        }
    }

    /// @dev M3 – In every pool, `1 <= threshold <= quorum` whenever a set is active, covering the write paths
    ///      M6.e does not (`_installSession`, `unblockSession` restore). Vacuous while no set is active.
    function property_M3_threshold_leq_quorum() public {
        for (uint8 k; k < POOL_COUNT; k++) {
            PoolId pool = _poolAt(k);
            uint8 q = multiAdapter.quorum(REMOTE_CENTRIFUGE_ID, pool);
            uint8 thr = multiAdapter.threshold(REMOTE_CENTRIFUGE_ID, pool);

            lte(uint256(thr), uint256(q), "M3: threshold > quorum");
            if (q >= 1) gte(uint256(thr), 1, "M3: zero threshold over a non-empty adapter set");
        }
    }

    /// @dev M4 – Per session: sumPositive(votes) <= deliveries. Votes live under `ghost_voteKey` =
    ///      `keccak256(routedPoolId ++ sessionId ++ payload)`; a wrong key reads all-zero and passes vacuously.
    function property_M4_vote_sum_bounded() public {
        uint256 n = ghost_tracked.length;

        for (uint256 i; i < n; i++) {
            SessionPair memory p = ghost_tracked[i];
            uint8 q = multiAdapter.quorum(p.centrifugeId, p.poolId);

            bytes32 voteKey = ghost_voteKey[p.centrifugeId][p.poolId][p.payloadHash];
            int16[MAX_ADAPTER_COUNT] memory v = multiAdapter.votes(p.centrifugeId, voteKey);
            uint256 positiveSum;
            for (uint8 j; j < q; j++) {
                if (v[j] > 0) positiveSum += uint16(v[j]);
            }

            uint256 deliveries = ghost_deliveries[p.centrifugeId][p.poolId][p.payloadHash];
            lte(positiveSum, deliveries, "M4: positive vote sum > deliveries");
        }
    }

    // ─── Gateway invariants ───────────────────────────────────────────────────

    /// @dev G1 – isBatching is false between transactions. Transient storage resets per tx: near-tautological.
    function property_G1_isBatching_false() public {
        t(!gateway.isBatching(), "G1: isBatching is true between transactions");
    }

    /// @dev U6 – the gateway's unpaid-batch counter equals the harness ledger for every batch ever retained.
    ///      Each retained send adds exactly one instance and each settled repay consumes exactly one, and
    ///      that correspondence must survive whatever the fuzzer interleaves in between: a pause, a
    ///      `blockSession`, a session reconfigure. `Gateway.underpaid` has no session component, so a
    ///      reconfigure must NOT strand, duplicate or silently clear an outstanding instance.
    function property_U6_underpaid_ledger_matches() public {
        uint256 n = ghost_underpaidTracked.length;
        for (uint256 i; i < n; i++) {
            TrackedPair memory p = ghost_underpaidTracked[i];

            (, uint64 counter) = gateway.underpaid(p.centrifugeId, p.payloadHash);
            eq(
                uint256(counter),
                ghost_underpaidOutstanding[p.centrifugeId][p.payloadHash],
                "U6: gateway underpaid counter diverged from the harness ledger"
            );
        }
    }

    /// @dev The adapter cost quote is a test fixture, not protocol state. It is raised only inside the
    ///      underpaid-batch handlers and must be restored before the transaction ends, because a non-zero
    ///      quote silently diverts every ordinary send onto `_send`'s unpaid branch. This makes that
    ///      confinement self-checking instead of a comment: it is trivially true today, and fails loudly
    ///      if a future handler leaks a raised quote.
    function property_adapterEstimate_zero_between_txs() public {
        eq(adapter0.estimatePerCall(), 0, "estimate: adapter0 quote leaked out of a handler");
        eq(adapter1.estimatePerCall(), 0, "estimate: adapter1 quote leaked out of a handler");
        eq(adapter2.estimatePerCall(), 0, "estimate: adapter2 quote leaked out of a handler");
        eq(underlying.estimatePerCall(), 0, "estimate: underlying quote leaked out of a handler");
    }

    /// @dev SB1 – the standby's credit for every payload it was ever sent equals the harness ledger: credited
    ///      once per dispatch that included it, consumed once per forward. Written as an addition so a missed
    ///      dispatch record fails here instead of underflowing into a discarded revert.
    function property_SB1_standby_credit_ledger() public {
        uint256 n = ghost_standbyPayloads.length;
        for (uint256 i; i < n; i++) {
            bytes32 id = _standbyId(ghost_standbyPayloads[i]);
            eq(
                standby.forwardable(id) + ghost_standbyForwarded[id],
                ghost_standbySent[id],
                "SB1: standby credit diverged from sends minus forwards"
            );
        }
    }

    /// @dev FO1 – the failover armed per pool equals the harness ledger: initiate arms it, cancel, veto and execute
    ///      disarm it, and nothing else moves it. Catches a disarm that leaves the proposal live (a vetoed set
    ///      installing later) as well as an execute that does not consume it.
    function property_FO1_failover_ledger() public {
        PoolId[2] memory pools = [POOL_A, POOL_B];
        for (uint256 i; i < pools.length; i++) {
            (uint64 executableAt, bytes32 paramsHash) = failover.pendingFailover(REMOTE_CENTRIFUGE_ID, pools[i]);
            eq(executableAt, ghost_failoverExecutableAt[pools[i]], "FO1: armed executableAt diverged from the ledger");
            bytes32 expected = executableAt == 0 ? bytes32(0) : _failoverParamsHash(pools[i]);
            t(paramsHash == expected, "FO1: armed params diverged from the ledger");
        }
    }

    /// @dev G2 – Per session: (callCount + failedMessages) * threshold <= deliveries. One gateway.handle() per
    ///      threshold reach; retry() moves a count from failedMessages to callCount, preserving the sum.
    function property_G2_execution_conservation() public {
        uint256 n = ghost_tracked.length;

        for (uint256 i; i < n; i++) {
            SessionPair memory p = ghost_tracked[i];
            uint256 threshold_ = uint256(multiAdapter.threshold(p.centrifugeId, p.poolId));

            uint256 deliveries = ghost_deliveries[p.centrifugeId][p.poolId][p.payloadHash];
            uint256 calls = countingProcessor.callCount(p.centrifugeId, p.payloadHash)
                - ghost_baselineCallCount[p.centrifugeId][p.poolId][p.payloadHash];
            // Saturating: retry/clear can push failedMessages below the baseline captured at first track.
            uint256 failedNow = gateway.failedMessages(p.centrifugeId, p.payloadHash);
            uint256 failedBase = ghost_baselineFailedMessages[p.centrifugeId][p.poolId][p.payloadHash];
            uint256 failed = failedNow > failedBase ? failedNow - failedBase : 0;

            lte((calls + failed) * threshold_, deliveries, "G2: (callCount + failedMessages) * threshold > deliveries");
        }
    }

    /// @dev G3 – retry reverts for a message that has not failed; enforced in `gateway_retry_nonFailed_mustRevert`.

    /// @dev G4 – Per session: failedMessages <= deliveries, since `_safeProcess` fails at most once per handle.
    function property_G4_failed_messages_bounded() public {
        uint256 n = ghost_tracked.length;
        for (uint256 i; i < n; i++) {
            SessionPair memory p = ghost_tracked[i];

            // Saturating diff: see G2 for why failedMessages can drop below its baseline.
            uint256 failedNow = gateway.failedMessages(p.centrifugeId, p.payloadHash);
            uint256 failedBase = ghost_baselineFailedMessages[p.centrifugeId][p.poolId][p.payloadHash];
            uint256 failed = failedNow > failedBase ? failedNow - failedBase : 0;

            uint256 deliveries = ghost_deliveries[p.centrifugeId][p.poolId][p.payloadHash];
            lte(failed, deliveries, "G4: failedMessages > deliveries");
        }
    }

    /// @dev G5 / G5b / G6 – pause and session-block enforcement, in `gateway_handle_whenPaused_mustRevert`,
    ///      `gateway_retry_whenPaused_mustRevert` and `gateway_send_whenBlocked_mustRevert` (G6: EmptyAdapterSet).

    // ─── Cross-session (cumulative) invariants ───────────────────────────────

    /// @dev M1c – Across ALL sessions: sum(callCountDelta * thresholdAtObservation) <= cumulativeDeliveries.
    ///      Arithmetic only; structural replay is covered by `multiAdapter_alex1_replay_must_not_execute`.
    function property_M1c_weighted_executions_bounded_by_deliveries() public {
        uint256 n = ghost_cumTracked.length;
        for (uint256 i; i < n; i++) {
            TrackedPair memory p = ghost_cumTracked[i];

            uint256 weighted = ghost_cumExecutionsWeighted[p.centrifugeId][p.payloadHash];
            uint256 delivs = ghost_cumDeliveries[p.centrifugeId][p.payloadHash];
            lte(weighted, delivs, "M1c: weighted-executions > cumulative-deliveries");
        }
    }

    /// @dev `countingProcessor.callCount[cId][hash]` never decreases (structurally true: the mock is unsigned).
    function property_callCount_monotonic() public {
        uint256 n = ghost_cumTracked.length;
        for (uint256 i; i < n; i++) {
            TrackedPair memory p = ghost_cumTracked[i];

            uint256 cur = countingProcessor.callCount(p.centrifugeId, p.payloadHash);
            uint256 lastSeen = ghost_cumLastSeenCallCount[p.centrifugeId][p.payloadHash];
            gte(cur, lastSeen, "callCount: decreased between handlers");
        }
    }

    // Session-id monotonicity is asserted inside `multiAdapter_reconfigure`, the only handler that mutates it.
}
