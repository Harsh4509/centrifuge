# Messaging Tester

Recon/Chimera invariant suite for `MultiAdapter` + `Gateway` in isolation, with no Hub, Spoke or Vaults, plus the two contracts that act on them from the adapter side: `StandbyAdapter` and `AdapterFailover`.

It covers the inbound voting flow (`MultiAdapter.handle`/`vote`/`execute` → `Gateway.handle`), the outbound send path (`Gateway.send` → `MultiAdapter.send` → adapter), `retry`/`clearFailedMessage`/pause/`blockSession`-`unblockSession`, source-chain enforcement, adapter reconfiguration across sessions, and the `AdapterFailover` lifecycle (steward arms a set, timelock, permissionless execute into `setAdapters`, steward cancel and hub veto).

Sister suite is [`test/integration/recon-end-to-end/`](../recon-end-to-end/) (Hub + Vaults). Properties and ghosts are scoped to one suite each, so don't conflate them.

## What is real and what is mocked

**The contracts under test are the real ones.** `Setup.sol` deploys `new Gateway(...)` and `new MultiAdapter(...)` directly from `src/core/messaging/`, a real `StandbyAdapter` from `src/adapters/` and a real `AdapterFailover` from `src/managers/adapters/`. There is no `MockGateway` or `MockMultiAdapter` here, unlike the end-to-end suite which stubs the gateway.

Mocks exist only at the four peripheral interfaces the two contracts talk to, plus one non-ward actor:

| Interface | Mock | Why |
|---|---|---|
| `IAdapter` | `mocks/SimpleAdapter.sol` | no real bridge in-process; one instance with the standby as its entrypoint is the adapter a `StandbyAdapter` relays through, and records what `forward` hands it |
| `IMessageHandler`, `IMessageParser` | `mocks/CountingProcessor.sol` | observable per-payload execution count; the framing view Gateway/MultiAdapter authenticate with |
| `IMessageGas`, `IAdapterGasService` | `mocks/MockMessageGas.sol` | fixed gas limits and standby receive cost, independent of the real `GasService` pricing |
| `IProtocolPauser` | `mocks/MockProtocolPauser.sol` | freely togglable pause |
| n/a | `mocks/ManagerActor.sol` | a non-ward caller, to exercise the manager roles on both contracts |
| n/a | `mocks/StewardActor.sol` | the `AdapterFailover` steward; the test contract is the envoy, so a separate steward lets negatives call `fromHub` as a non-envoy and the steward entry points as a non-steward |
| n/a | `mocks/BatcherActor.sol` | `withBatch` calls back into `msg.sender`, so the batch initiator must be a contract |

Consequence for coverage reports: `src/core/messaging/{Gateway,MultiAdapter}.sol` **must** show substantial line coverage after a real campaign. As of the current tip a 3M-call Echidna run gives `MultiAdapter` 147/149 and `Gateway` 158/162, with the batching path also covering every logic line of `TransientArrayLib`, `TransientStorageLib` and, through the long-message batches, `TransientBytesLib`. Every `Gateway` and `MultiAdapter` LOGIC line is covered: the remaining 4 and 2 are state/immutable declarations, which Echidna does not attribute. Coverage of `src/` saturates early: a 3M local run and a 100M Recon Cloud run produced byte-identical per-file numbers, so a shortfall there is a missing handler, not a short campaign. The harness's own cross-session branches are slower: a fresh-corpus 3M run missed `gateway_retry`'s baseline bump for a failure funded before the session, which the accumulated corpus reaches. That is why the corpus is kept across handler additions (see Config and corpus). A report showing 0 for either is an attribution bug in the build, not an accurate measurement. See [Coverage attribution](#coverage-attribution) below.

## Messaging-layer surface under test

- Sessions are per-(`centrifugeId`, `poolId`) `uint16`. Inbound payloads are wrapped with a 2-byte sessionId prefix, and an unwrapped or mis-wrapped payload reverts `InvalidAdapter`.
- Votes are pool-namespaced: `_votes[cId][voteKey]` where `voteKey = keccak256(abi.encodePacked(routedPoolId, wrappedPayload))`. A global-set vote and a pool-set vote on identical bytes no longer share a slot.
- `setAdapters(cId, pool, adapters, threshold, targetSessionId)` takes 5 args. `targetSessionId` must equal `nextActiveSessionId(cId, pool)` (active + 1) or it reverts `UnexpectedSessionId()`. A `threshold == 0` over a non-empty set reverts `ZeroThreshold()`.
- Session ids plain-increment. There is no wrap from max back to 1 and no skip of 0, so at `type(uint16).max` `setAdapters` panics `0x11` and that (cId, pool) is exhausted permanently. Session id 0 therefore always means "never configured".
- `AdapterFailover.executeFailover` installs through `setAdapters` as a per-pool MultiAdapter manager (not a ward), at `nextActiveSessionId` read when it executes: a proposal is not bound to the session it was armed under, and a hub reconfigure or a blocked session in between does not disarm it. Only `cancelFailover` or the hub's `CancelFailover` does.
- `blockSession`/`unblockSession`, the `vote`/`execute` split, `Gateway.clearFailedMessage`, and the `CannotBeReceivedLocally`/`SourceMismatch` guards are all in scope. `Gateway.blockOutgoing` and `recoveryIndex` no longer exist.

## File map

| File | Role |
|------|------|
| `Setup.sol` | Deploys Gateway + MultiAdapter + 3 `SimpleAdapter` mocks. Wires wards. Defines constants `THRESHOLD=2`, `ADAPTER_COUNT=3`, `LOCAL_CENTRIFUGE_ID=1`, `REMOTE_CENTRIFUGE_ID=2`, and three pools: `GLOBAL_POOL=PoolId(0)` and `POOL_A`, both configured with the same three adapters at threshold 2, and `POOL_B`, left unconfigured (see [Pools](#pools)). Defines `_route(payload)`, the pool whose set carries a payload right now, mirroring `MultiAdapter._routePoolId`; `_wrap(payload)`, which prefixes that pool's active sessionId (2 bytes) and which EVERY inbound delivery must use (unwrapped payloads revert `InvalidAdapter`); `_voteKey(pool, wrapped)`, the `multiAdapter.votes` key `keccak256(uint64 poolId ++ wrapped)`, where the `uint64` width is load-bearing; `_activeList(pool)`/`_isActive(pool, adapter)` for live active-set reads; and `_poolAt(seed)` for the pool-seeded handlers. Deploys the real `AdapterFailover` last (envoy = the test contract, `FAILOVER_TIMELOCK = 2 days`), gives it the MultiAdapter manager role on `POOL_A` and `POOL_B`, never the global pool, and makes `mocks/StewardActor.sol` steward of `POOL_A`; `_failoverPoolAt(seed)` picks between those two pools. |
| `BeforeAfter.sol` | Ghost variables. Two layers: per-session, keyed by (cId, routed pool, hash) and reset per pool via `_clearTrackedDeliveries(pool)`, for the M1/M4/G2/G4 bound checks; and cumulative / cross-session, keyed by (cId, hash) and NEVER reset, for M1c and callCount monotonicity. `_captureBaselines` (pre-deliver) + `_recordSuccessfulDelivery` (post-success) split, so reverts don't pollute ghosts. `ghost_voteKey[cId][pool][hash]` holds the pool-namespaced vote key. `_recordQuorumEvent` credits the cumulative ledger at the routed pool's threshold (`execute()` uses it without a delivery increment); `_syncCumCounters` absorbs vote-free moves (`retry`, `clearFailedMessage`, the gateway manager). Top-level `TrackedPair` (cumulative and underpaid ledgers) and `SessionPair` (per-session) structs. No active-set ghost: targets read `_activeList(pool)` live. The failover ledger (`ghost_failoverExecutableAt` / `Adapters` / `Threshold` per pool, on `REMOTE_CENTRIFUGE_ID`) holds the proposal the harness believes is armed: written by `failover_initiate`, cleared by cancel, veto and execute. |
| `targets/MultiAdapterTargets.sol` | `multiAdapter_deliver{,All,ToThreshold}`, `multiAdapter_vote`, `multiAdapter_execute` (positive); `multiAdapter_deliverBatch` (a 2-3 message inbound batch whose messages name one pool; asserts G12 inline: an executed batch processes each message exactly once per occurrence, executed or recorded as failed, and an unexecuted one processes none; for the delivery-bound ghosts a batch delivery is one delivery of each message it carries); `multiAdapter_reconfigure(countSeed, thresholdSeed)` on the global pool, `multiAdapter_reconfigurePool(poolSeed, ...)` on any pool and `multiAdapter_reconfigureWithStandby(poolSeed, thresholdSeed)` installing [adapter0, adapter1, standby], including POOL_B's first configuration (state-mutating; clears that pool's per-session ghosts; asserts inline that `nextActiveSessionId == activeSessionId + 1` and that the call installs exactly that id, the only coverage of that getter); `multiAdapter_blockSession` (on the payload's routed pool)/`multiAdapter_unblockSession{,Pool}` (state-mutating, inline asserts on the blocked flag, active-set cleared/restored, blocked-session delivery rejected); manager path `multiAdapter_updateManager{,Pool}` (toggles the per-pool role for the non-ward `mocks/ManagerActor.sol`) and `multiAdapter_managerDeliver` / `multiAdapter_managerVote` / `multiAdapter_managerExecute` (the 3-arg `handle` / `vote` / `execute` on behalf of an active adapter, sharing the adapter handlers' bodies and asserts); negatives M6.a/b/d/e/f (`setAdapters`: `ExceedsMax` / `ThresholdHigherThanQuorum` / `NoDuplicatesAllowed` / `ZeroThreshold` / `UnexpectedSessionId`), B1/B2 (block/unblock), V2 (execute below threshold → `NotEnoughVotes`), MA1/MA1b (non-manager on-behalf `handle` / `vote` / `execute` → `NotAuthorized`), M7 (`file` with an unknown param → `FileUnrecognizedParam`, negative only, mirroring G10), `multiAdapter_oldAdapter_mustRevert`, `multiAdapter_alex1_replay_must_not_execute`. Defines the `validPayload` modifier. |
| `targets/GatewayTargets.sol` | `gateway_send` (cId clamped to the configured route with a rare escape; asserts S1 fan-out hits every adapter of the routed pool's active set exactly once, plus S2 payload wrapped with that pool's active sessionId), `gateway_retry` (cId clamped; baseline-bump when the consumed failure predates the session baseline), `gateway_clearFailedMessage`, `gateway_setPaused`, `gateway_setProcessorFail(bytes payload, bool)` which takes a bucketed payload rather than a free `bytes32`, and that is what makes the fail→retry/clear cycle fuzzer-reachable; negatives G3 (retry non-failed), G5/G5b (pause), G6 (send after `blockSession` of the active session → `EmptyAdapterSet`), G7 (clear non-failed), G8 (local-origin batch → `CannotBeReceivedLocally`), G9 (source-restricted message from the wrong chain → `SourceMismatch`), G11 (an inbound batch whose messages name different pools → `MalformedBatch`). Outbound batching via `mocks/BatcherActor.sol`: `gateway_withBatch` (bucketed messages span the pools; asserts BT1 `isBatching` false on return, BT2 that each pool the messages name gets exactly ONE dispatch through its routed set, so a shared adapter is sent once per pool, BT3 that each dispatch is the session-wrapped concatenation of that pool's messages, told apart by `SimpleAdapter.sentCount`), `gateway_withBatch_explicitValue` (3-arg overload), `gateway_withBatch_nested` (only the outermost batch settles, so nesting appends to a pool's slot and is still one dispatch per pool), `gateway_withBatch_longMessages` (messages longer than a 32-byte transient chunk, so every append crosses chunk boundaries and BT3 checks the multi-chunk batch storage); negatives BT4-BT7 (`CallbackWasNotLocked` / `CallbackWasNotFromSender` / `CallFailedWithEmptyRevert` / `CallbackIsLocked`). Underpaid batches, split so the state crosses a transaction boundary: `gateway_send_underpaid` (quote non-zero → send → restore quote, LEAVING the batch outstanding; asserts U1 retention and U7 that a retained batch never reaches the adapter) and `gateway_repay` (settles it; asserts U2 single-instance consumption and U3 dispatch-on-repay). `shortcut_gateway_repay_underpaid` keeps the whole cycle in one transaction so the `repay` lines stay covered even if the fuzzer rarely pairs the halves; it touches no ledger ghost by design, since retention and settlement cancel within the transaction. Negatives U4 (`NotEnoughGas`), U5 (`NotUnderpaidBatch`). The retaining handlers and U4 need a priced adapter in the routed set: the standby's `estimate` is pure 0, so a standby-only set (which Alex-1 can leave behind) sends on zero fuel and has no unpaid branch. Admin: `gateway_updateManager{,Pool}` (toggles the gateway-side per-pool manager role for `ManagerActor`, asserting the getter round-trips; the gateway checks the pool the message names, MultiAdapter the routed pool). Pool manager, the quorum bypass: `gateway_managerHandle` (asserts MG1, that each submitted message is processed exactly once, executed or recorded as failed; it casts no votes, so it moves the per-session baselines and syncs the cumulative counters the way `gateway_retry` does) and `gateway_managerClearFailedMessage` (same asserts as the ward clear); negatives MG2/MG3 (`handle` / `clearFailedMessage` without the gateway role of the message's pool → `NotAuthorized`, whatever the other roles). Negative G10 (`file` with an unknown param -> `FileUnrecognizedParam`; only the negative is fuzzed, since a positive `file` handler would let the fuzzer repoint `processor`/`adapter` at an arbitrary address and invalidate the suite). Inherits `MultiAdapterTargets`. |
| `properties/MessagingProperties.sol` | Per-session, at each entry's routed pool: M1 (which is also the cross-pool vote-namespacing check), M2 and M3 over every pool (M2 via the 4-arg `adapters(cId,pool,sid,i)` getter; (`1 <= threshold <= quorum` whenever a set is active; the lower bound is the always-on form of the `ZeroThreshold` fix, covering write paths other than `setAdapters`), M4 (reads votes via `ghost_voteKey`), G1, G2, G4 (G2/G4 use saturating baseline diffs, since retry/clear can push `failedMessages` below baseline). U6 (`property_U6_underpaid_ledger_matches`: the gateway's unpaid-batch counter equals the harness ledger for every batch ever retained, so whatever the fuzzer interleaves between retention and settlement must not strand, duplicate or silently clear an instance). Fixture guard: `property_adapterEstimate_zero_between_txs` asserts the adapter cost quote is back to zero between transactions, making the confinement rule for `SimpleAdapter.estimatePerCall` self-checking. Cumulative cross-session: M1c, callCount monotonicity. G3/G5-G9, B1/B2 (block/unblock), BT4-BT7 (batching callback), U4/U5 (underpaid) and V1/V2 are enforced inline in the targets instead. SB1 (`property_SB1_standby_credit_ledger`: the standby's credit for every payload it was sent equals harness sends minus forwards, written as an addition so a missed record fails instead of underflowing). FO1 (`property_FO1_failover_ledger`: `pendingFailover` on both failover pools equals the harness ledger, so a disarm that leaves a proposal live, or an execute that does not consume it, fails here). |
| `targets/StandbyTargets.sol` | The StandbyAdapter's own surface. `standby_forward` (asserts SB2: one credit consumed, the same bytes relayed once through the underlying with gas `(gasLimit + receiveCost) * 64/63`, the caller refunded). Negatives SB3 (forward without a credit → `NotForwardable`), SB3b (a credited payload under another gas limit → `NotForwardable`), SB4 (forward below the underlying's quote → `NotEnoughValue`), SB5 (`send` from anyone but the MultiAdapter → `NotEntrypoint`), SB6 (`handle`/`vote`/`execute` from anyone but the underlying → `NotUnderlying`). Credits come from the gateway targets' dispatches while the standby is in a set; its inbound votes go through `_inbound`. Inherits `GatewayTargets`. |
| `targets/FailoverTargets.sol` | `AdapterFailover`'s lifecycle. Time moves only through the fuzzer's block delays (`--max-time-delay 604800`, a week, against a 2-day timelock), which land before, inside and past the window. Hub side, called as the envoy: `failover_updateSteward` (FO5: the steward role is per pool, the other pool's flag never moves), `failover_hubVeto` (FO4). `failover_updateManager` toggles the failover's MultiAdapter manager role per pool. Steward side, through `StewardActor`: `failover_initiate` (FO3: armed at `now + timelock` with the hash of the exact set; the set is a non-empty subset of the three simple adapters and the standby), `failover_stewardCancel` (FO4). `failover_execute` (FO2, liveness and exactness: a proposal armed and not disarmed, inside its window, on a pool holding the role, always installs, whatever reconfigured, blocked or voted on the pool meanwhile; it installs exactly the armed set and threshold as the next session and is consumed; clears the pool's per-session ghosts as `_install` does). Negatives FO6 `failover_execute_early_mustRevert` (before the window → `TimelockNotElapsed`), FO7 `failover_execute_expired_mustRevert` (past it → `FailoverExpired`), FO8 `failover_execute_unarmed_mustRevert` (nothing armed for any chain and pool, the global one included → `NoPendingFailover`), FO9 `failover_execute_wrongParams_mustRevert` (other params inside the window → `ParamsMismatch`), FO10 `failover_execute_noRole_mustRevert` (no MultiAdapter role → `NotAuthorized`), FO11 `failover_notSteward_mustRevert` (non-steward initiate or cancel → `NotSteward`), FO12 `failover_initiate_zeroThreshold_mustRevert` (zero threshold → `InvalidThreshold`), FO13 `failover_fromHub_notEnvoy_mustRevert` (`fromHub` from a non-envoy → `NotEnvoy`). Inherits `StandbyTargets`. |
| `TargetFunctions.sol` | Aggregator: `is FailoverTargets, MessagingProperties` (FailoverTargets pulls in StandbyTargets, GatewayTargets and MultiAdapterTargets transitively). |
| `CryticMessagingTester.sol` | Fuzzer entry point. Run with `--config echidna-messaging.yaml` from the project root. |
| `CryticToFoundry.sol` | Foundry harness. 79 deterministic tests: smoke, C1/H3 regressions, M6.a-f negatives, vote-key pinning, vote/execute, blockSession, clearFailedMessage, source enforcement, Alex-1, M1c cross-session retry, outbound batching (BT1-BT7, including the unbatched contrast case that pins coalescing as real), underpaid batch / repay (U1-U7, including cross-transaction persistence, survival across a reconfigure, and instance stacking), gateway admin (`updateManager` round-trip, `file` unrecognized param on both contracts), gateway pool manager (executions and failures interleaved with quorum deliveries of the same payload keep every delivery bound, the unabsorbed contrast case that pins the baseline move as real, and role separation between the two contracts), MultiAdapter manager vote/execute, multiple pools (fallback votes stay in the global tally, a three-pool batch dispatches once per pool, manager roles are pool-scoped, a reconfigure clears only its pool's entries), a batch of long messages across transient chunks, multi-message inbound batches (per-occurrence processing, per-message failure and retry, mixed-pool rejection, the handler keeping every bound), StandbyAdapter (credit then forward, its inbound vote counting toward quorum, every negative), AdapterFailover (arm → timelock → execute, steward cancel and hub veto, a proposal surviving a reconfigure and a blocked session, a failover as POOL_B's first configuration, expiry, per-pool stewards, every negative). |
| `mocks/SimpleAdapter.sol` | Stub `IAdapter`. `deliver`→handle, `deliverVote`→vote, `deliverExecute`→execute, all expecting session-WRAPPED payloads. `send` records `sendCount`, `lastSentPayloadHash` and per-hash `sentCount` for S1/S2 and multi-pool batch observability, and returns `bytes32(0)`. `estimate` returns the settable `estimatePerCall`, **zero by default and load-bearing**: `Gateway._send` dispatches whenever `fuel >= cost`, and the suite holds no ETH, so a zero quote is what lets ordinary sends dispatch at `msg.value == 0`. A non-zero quote flips `_send` onto its unpaid / `NotEnoughGas` branches, so it is only ever raised inside the underpaid-batch handlers and restored in the same transaction. |
| `mocks/BatcherActor.sol` | Outbound-batching initiator. `Gateway.withBatch` calls back into `msg.sender`, so the initiator must be a contract that calls `lockCallback()` and issues its `send`s from inside that callback; the test contract cannot play this role. A `Mode` enum selects the path: `Normal`, `SkipLock` (→ `CallbackWasNotLocked`), `ForeignLock` (the peer instance locks → `CallbackWasNotFromSender`), `EmptyRevert` (→ `CallFailedWithEmptyRevert`), `Nested` (→ the `isNested` branch). Setup deploys two instances; `batcher` is a gateway ward because `send` is `auth`, `batcherPeer` needs none. |
| `mocks/CountingProcessor.sol` | `IMessageHandler` + `IMessageParser` mock. `callCount[cId][hash]` per (cId, UNWRAPPED payloadHash). `setFail(...)` is intentionally unauthenticated. Frames by first byte: a message starting with a bucket byte (below `ONE_BYTE_BELOW`, which `setup()` checks equals `PAYLOAD_BUCKETS`) is that one byte, so concatenated bucketed payloads form a multi-message batch; any other message is the whole remaining batch. Routes by first byte, which for bucketed payloads is the bucket: 10-14 name `POOL_A`, `SET_POOL_B` (15) plays a `SetPoolAdapters` for `POOL_B` and so falls back to the global set while `POOL_B` is unconfigured, everything else is global. `messageSourceCentrifugeId`: messages starting with magic `0xFE` + `bytes2(source)` are source-restricted, everything else returns 0 meaning any. Exports the file-level `POOL_A`/`POOL_B` constants `Setup` uses. |
| `mocks/MockMessageGas.sol` | `IAdapterGasService` mock. Gas values only, plus `receiveCost=3_500` for the standby's forward: `messageProcessingGasLimit=200_000`, `messageFailureGasReserve=35_000`, `maxBatchGasLimit=10_000_000`. |
| `mocks/MockProtocolPauser.sol` | Trivial. `setPaused` is intentionally unauthenticated. |
| `mocks/ManagerActor.sol` | A non-ward address used to exercise the manager role: on `MultiAdapter` (3-arg `handle` / `vote` / `execute`) and on `Gateway` (`handle`, `clearFailedMessage`). The two roles are granted separately. |

## Property semantics

Read this before touching properties. There are two ghost lifetimes (per-session vs cumulative) and three hash domains.

### Hash domains

Mixing these up is the easiest way to break the suite, and the failure is often silent.

- **Unwrapped hash** `keccak256(payload)`. The domain of `countingProcessor.callCount`, `gateway.failedMessages`, and ALL ghosts (`ghost_deliveries`, `ghost_cum*`, baselines). Targets pass the UNWRAPPED payload to `_captureBaselines`/`_recordSuccessfulDelivery`.
- **Wrapped hash** `keccak256(2-byte sessionId ++ payload)`. What `SimpleAdapter.send` records as `lastSentPayloadHash`. Used ONLY by the outbound S1/S2 assertions in `GatewayTargets.sol` and the two Foundry send tests. It is not a vote key; do not "fix" these to `_voteKey`.
- **Vote key** `keccak256(uint64 routedPoolId ++ 2-byte sessionId ++ payload)`. The domain of `multiAdapter.votes`, via `_voteKey(pool, ...)`. Properties reading votes use `ghost_voteKey[cId][pool][unwrappedHash]`, captured at the first in-session track. It is session-scoped because the sessionId is inside the hashed bytes, and pool-scoped because of the prefix.

Reading the wrong vote key fails SILENTLY. `votes()` returns an all-zero array for an unknown key, so M4 reports `positiveSum == 0 <= deliveries` and passes vacuously, and V2's, Alex-1's and G5's clean-slate preconditions stop constraining anything. `test_voteKey_addresses_the_live_tally` is the guard: it asserts the vote key sees a live tally AND that the bare wrapped hash does not. Keep it.

The `uint64` width of the pool prefix matters, because `abi.encodePacked` contributes 8 bytes and not 32. A `uint256(0)` prefix compiles fine and addresses a different, permanently empty slot.

### Pools

Three pools share the three adapters. `GLOBAL_POOL` and `POOL_A` start with identical sets, so single-pool reasoning holds until the fuzzer reconfigures one of them. `POOL_B` starts unconfigured, and its only message is a `SetPoolAdapters` (`SET_POOL_B`), which `routePoolId` carries over the global set until POOL_B's first `setAdapters`, after which it travels over POOL_B's own set. Configuration is one-way: `activeSessionId` never returns to 0.

That fallback is the one way the same wrapped bytes can be voted under two pools: a global vote cast before the configuration and a POOL_B vote after it, both at session 1. Only the vote key's pool prefix keeps the tallies apart, and M1 per routed pool is what reports a shared tally (`test_fallback_votes_stay_in_the_global_tally` pins this; dropping the prefix in `MultiAdapter` makes M1 fail).

Two pool readings matter and differ for a fallback payload: the pool the message NAMES (`countingProcessor.messagePoolId`), which the gateway uses for its batch slots and its manager check, and the ROUTED pool (`_route`), which MultiAdapter uses for the adapter set, session, threshold, vote key and its manager check. Per-session ghosts key on the routed pool.

### Per-session ghosts (M1, M2, M3, M4, G1, G2, G4)

These evaluate against the current session of the entry's routed pool only, as bounds within a single `setAdapters` epoch of that pool. Enforced by:

1. `_captureBaselines` (pre-deliver) snapshots `countingProcessor.callCount(cId, hash)` and `gateway.failedMessages(cId, hash)` into `ghost_baselineCallCount` / `ghost_baselineFailedMessages`, on first track within the session.
2. Properties subtract those baselines from current values, to express "executions caused by this session's deliveries".
3. Every `setAdapters` on a pool calls `_clearTrackedDeliveries(pool)`, which deletes that pool's per-session entries, plus the global entries of messages naming the pool that the global set carried while it was unconfigured: their route has just moved, and `callCount` is per hash, so the stale entry would count the new pool's executions against the global pool's deliveries.

This pattern fixes the C1 bug class: M1/G2 read the current threshold but ghost counters span sessions, so a reconfigure that raises the threshold trips the property.

If you add a property that reads `multiAdapter.threshold(...)` or `multiAdapter.quorum(...)` and compares it to anything counted across deliveries, mirror the baseline pattern. Otherwise the property will trip on reconfigure.

### Cumulative cross-session ghosts (M1c, callCount monotonicity)

These are NEVER reset by reconfigure. They validate that protocol behaviour stays correct across session transitions, which is the original motivation for the suite: an adapter-set reconfiguration must not let a stale, already-counted delivery execute a second time.

- `ghost_cumDeliveries[cId][hash]`: total deliveries forever.
- `ghost_cumExecutionsWeighted[cId][hash]`: sum of `(callCount_delta × threshold_at_observation)` for each detected execution.
- `ghost_cumLastSeenCallCount[cId][hash]`: last observed callCount, for delta detection and monotonicity.
- `ghost_cumTracked` / `ghost_isCumTracked`: list of all (cId, hash) pairs ever delivered.

The pre-deliver `_captureBaselines` + post-success `_recordSuccessfulDelivery` split ensures reverts pollute neither domain.

### M2 is a real cross-storage invariant

It iterates `multiAdapter.adapters(cId, pool, activeSessionId, i)` and asserts pairwise distinctness and non-zero. Don't replace it with `quorum == ghost_adapterCount`, which was the original tautology.

### Alex-1 replay (`multiAdapter_alex1_replay_must_not_execute`)

This PASSES under the multi-session design, because votes are keyed by a session-bearing key, so a stale replay counts under the OLD session's threshold of ≥ 2 and cannot re-execute. The target replays the original wrapped bytes (stale sessionId prefix) and asserts callCount is unchanged; it stays live as a regression guard. Preconditions are a clean vote slate for the wrapped payload and threshold ≥ 2, since threshold-1 duplicate re-execution is by-design parallel-message semantics rather than the replay bug. The complementary kill-switch is `blockSession` on the old session, which rejects stale replays outright and is asserted inline in `multiAdapter_blockSession`.

## Conventions for adding handlers and properties

1. **Negative `*_mustRevert` targets must use selector-checked catches.** An empty `catch {}` swallows wrong-reason reverts and silently passes the property. Always:

   ```solidity
   try someCall() {
       t(false, "...: should have reverted");
   } catch (bytes memory err) {
       t(bytes4(err) == ISomeInterface.ExpectedError.selector, "...: wrong revert");
   }
   ```

2. **Use the `_captureBaselines` (pre-deliver) + `_recordSuccessfulDelivery` (post-success) split.** Capture happens before the on-chain effect, so executions caused by THIS delivery show up as a delta. The increment happens only on success, so reverts don't pollute ghosts. Never call the post-hook outside the success branch.

3. **Payload keyspace is bounded to `PAYLOAD_BUCKETS` (16) via `_bucket(payload)` in `Setup.sol`, not via `validPayload`.** `validPayload` is only a length guard. Every state-producing or failure handler canonicalizes its payload with `bytes memory p = _bucket(payload)` at entry and uses `p` thereafter. This is what makes multi-step sequences collide on the same (cId, hash), which matters most for the fail→retry/clear cycle: that cycle was fuzzer-unreachable while `gateway_setProcessorFail` took a free `bytes32` that never matched a delivered payload. `_bucket` is idempotent, so canonical 1-byte payloads pass through and Foundry tests can wrap their payload definition once with `_bucket(abi.encode(...))` and keep referencing `keccak256(payload)`. When adding a handler that must share the delivery/failure keyspace, canonicalize with `_bucket` and keep everything keyed off `p`.

4. **Per-session ghost reset.** Anything tracked per (cId, pool, hash) must be cleared in `_clearTrackedDeliveries(pool)`. Anything tracked per session, such as `ghost_adapterCount`, must be set in `setup()` and updated on reconfigure.

5. **Sentinel `t(true, ...)` properties are forbidden.** Live enforcement goes in negative target functions. Document the property in NatSpec near the target, not as a no-op property.

6. **The test contract (`address(this)`) is the deployer and ward** of both `Gateway` and `MultiAdapter`. `mocks/BatcherActor.sol` is additionally a `Gateway` ward, because `send` is `auth` and it must call it from inside the `withBatch` callback; that is additive, not a move to a per-actor pattern. Don't replace this with a per-actor pattern without re-thinking auth on the `onlyAuthOrManager` surfaces (`setAdapters`, `blockSession`/`unblockSession`, `gateway.handle`, `clearFailedMessage`) and on the `updateManager` / manager-submission paths `ManagerActor` exercises.

7. **Wrap every inbound payload with `_wrap(...)`** before handing it to an adapter mock, and pass the UNWRAPPED payload to the ghost helpers. To read votes, wrap first, then `_voteKey(...)`.

   In Foundry tests, hoist ANY staticcall into a local BEFORE `vm.expectRevert`. The expectation is armed first, so an argument evaluated after it consumes the expectation and the test fails with "call did not revert as expected". This bites `_wrap`/`_voteKey`, which read `activeSessionId`, and `nextActiveSessionId(...)` passed as the 5th argument to `setAdapters`.

   A Foundry test that calls a `*_mustRevert` handler expects `vm.expectRevert(bytes(""))`, never a bare `vm.expectRevert()`. A negative that holds ends in `require(false)`, which reverts with empty data; one that breaks reverts with its `t(false, ...)` message, which a bare expectation also accepts, so the test would pass on exactly the bug it exists for.

8. **State-mutating targets with inline asserts** (`multiAdapter_blockSession`, `multiAdapter_unblockSession`, `multiAdapter_reconfigure`, Alex-1) must NOT end with `require(false)`. Their state change is the point.

9. **Adapter activeness is always read LIVE** via `_activeList(pool)`/`_isActive(pool, adapter)` in `Setup.sol`, never mirrored in a ghost. The Alex-1 target installs non-prefix sets such as `[adapter1]`, and a "first N of adapter0..2" count ghost misrepresents them. That produced false positives in `oldAdapter_mustRevert` and V2.

10. **Test fixtures that change protocol behaviour must be restored in the SAME transaction.** `SimpleAdapter.estimatePerCall` (on the three adapters and on the standby's underlying) is the only one: a non-zero quote diverts every send onto `Gateway._send`'s unpaid branch, so `gateway_send_underpaid` (whose batch stays outstanding across transactions, so restoring the quote matters most there), `shortcut_gateway_repay_underpaid`, `gateway_send_notEnoughGas_mustRevert` and `standby_forward_underpaid_mustRevert` raise it and set it back to 0 before returning. Echidna runs each handler as its own transaction, so no other handler can observe a raised quote and a revert rolls the raise back; the hazard is a *swallowed* revert, since a `catch` does not undo state already changed in the outer frame. Restore before the `catch`, not after it. `property_adapterEstimate_zero_between_txs` enforces this.

## Running

```bash
# Foundry: fast, deterministic, 79 tests
forge test --match-contract CryticMessagingToFoundry -vv

# Single test
forge test --match-test test_C1_M1_after_threshold_increase_reconfigure -vvv
```

### Echidna takes the FILE target

```bash
FOUNDRY_PROFILE=echidna echidna test/integration/recon-messaging/CryticMessagingTester.sol \
  --contract CryticMessagingTester --config echidna-messaging.yaml --test-limit 3000000 --workers 8
# quick local smoke: drop --test-limit (Echidna default 50k)
```

Run the file target, not `echidna .`. Both compile — `EnvConnections.load` used to be a `public` library
function needing linking that whole-project compilation could not provide, but it is `internal` now — the
reason that survives is parity: the file target is what Recon Cloud uses, so running it locally keeps the
two in sync.

### `recon fuzz` takes the OPPOSITE target

```bash
FOUNDRY_PROFILE=echidna recon fuzz . \
  --contract CryticMessagingTester --config echidna-messaging.yaml --workers 16 --test-limit 10000
```

`recon fuzz` (Recon's own Rust fuzzer) wants a Foundry project path, not a file. Passing the `.sol` file fails with "Failed to compile project / Failed to run forge build (No such file or directory)". It does not go through crytic-compile, so the file-target rule above does not apply to it.

`--recon-corpus-dir <dir>` keeps recon's corpus separate and auto-exports an Echidna-compatible copy into `corpusDir`, so the same yaml serves both fuzzers without them fighting.

### Coverage attribution

`FOUNDRY_PROFILE=echidna` is required for every fuzzer invocation, not optional.

The profile sets `bytecode_hash = "ipfs"` and `cbor_metadata = true`. `[profile.default]` sets them to `"none"` and `false` so that deployed bytecode stays deterministic, and that is correct for production but wrong for fuzzing. Without a CBOR metadata trailer, hevm keys its coverage map on the full runtime bytecode. Immutables are patched into runtime bytecode at deploy time, so any separately deployed contract with constructor-set immutables no longer matches its compiled artifact and gets no coverage attributed at all.

Measured on the same command, changing only the profile:

| | default profile | `FOUNDRY_PROFILE=echidna` |
|---|---|---|
| `MultiAdapter.sol` | 1/312 combined | 145/147 |
| `Gateway.sol` | (same 1/312) | 80/162 |
| `SimpleAdapter`, `ManagerActor` | 0 | 17/19, 5/6 |

Contracts inherited into `CryticMessagingTester` itself (`Setup`, `BeforeAfter`, targets, properties) are attributed either way, because Echidna knows that deployment by name. Mocks without immutables (`CountingProcessor`, `MockMessageGas`, `MockProtocolPauser`) are also attributed either way. So a report where the targets and properties look healthy but `Gateway` and `MultiAdapter` read 0 is diagnostic of a missing profile, not of an idle fuzzer.

The same missing metadata destabilises the coverage key, so every sequence looks like new coverage, which grows the corpus without bound and eventually OOMs.

### Config and corpus

`echidna-messaging.yaml` deliberately omits `testLimit`, `workers`, `seqLen`, `timeout`, `symExec` and `seed`, so it works on Recon Cloud (where the UI governs run params) and locally (where CLI flags do). Do NOT add a `timeout`, since it would cap a long cloud campaign early.

Compilation takes roughly 150s because the project is large with many libraries, so the first run is the slowest. The corpus persists in `corpusDir: echidna-messaging` at the project root.

**Wipe the corpus when an existing handler's signature changes** (`rm -rf echidna-messaging/`). Entries name the handler and carry its concrete arguments, so entries recorded before the change either decode into a different call or get discarded, and the campaign restarts from a corpus that no longer means what it says. **Keep it when handlers are only added** or their bodies change: old entries still replay as recorded, and a fresh corpus can take far longer than one campaign to reach the multi-step paths the old one holds.

### Recon Cloud (getrecon.xyz/dashboard/jobs)

- Path to test contract: `test/integration/recon-messaging/CryticMessagingTester.sol`
- Echidna config filename: `echidna-messaging.yaml`, Tester Contract Name: `CryticMessagingTester`
- Corpus Dir: `echidna-messaging`, Mode: assertion, Fork Mode: Non-Forked
- Branch: the branch under test, committed and pushed first. Test Limit: 10M for the first (no-corpus) run.
- Corpus Reuse Job ID: LEAVE EMPTY. The corpus is suite-specific, so never paste the recon-end-to-end job id. Once a run completes, reuse ITS job id for subsequent higher-limit messaging runs.

Cloud jobs currently build with the default foundry profile, so treat `src/**` coverage from a cloud report as unusable until that is resolved. Property results are unaffected, since only the source mapping breaks.

## Setup constants

- `THRESHOLD=2`, `ADAPTER_COUNT=3`. The initial `setAdapters` calls in `setup()` create session 1 of `GLOBAL_POOL` and of `POOL_A`; `POOL_B` has no session until the fuzzer configures it.
- `multiAdapter_reconfigure` fuzzes count in [1,3] and threshold in [1,count], where threshold ≥ 1 keeps it clear of the `ZeroThreshold` guard. Session ids are per-(cId, pool) `uint16` and increment by exactly 1 per `setAdapters`, and the caller must pass that id as `targetSessionId`.
- `MAX_ADAPTER_COUNT=8` from `IMultiAdapter.sol`. The M6.a negative deliberately exceeds it.
- `PAYLOAD_BUCKETS=16`, the bounded payload keyspace behind `_bucket(...)`.
- `messageOverallGasLimit` returns `0` (unpaid mode), `messageProcessingGasLimit` returns `200_000`, `messageFailureGasReserve` returns `35_000`. Gateway forwards `gasLimit - reserve` to the processor, so the reserve must stay well below the processing limit.

## Known coverage gaps

These are deferred follow-ups rather than bugs in the existing suite. Each warrants its own PR, so don't add them ad-hoc. If you close one, update this section.

- **Outbound batching and underpaid batches are now covered**, so `property_G1_isBatching_false` is no longer a tautology: `isBatching` genuinely goes true within a transaction. What remains are BRANCH gaps whose lines all execute, so line coverage will not show them:
  - **`NotPayable`** (a send carrying value inside a batch) and a non-zero `withBatch` `callbackValue` both need the tester to hold ETH. `echidna-messaging.yaml` deliberately sets no `balanceAddr`/`balanceContract`, unlike `echidna.yaml`, so fuel is always 0. Adding a balance would change `msg.value` semantics for every payable handler and risks local/cloud divergence, so it is a deliberate deferral rather than an oversight.
  - **`BatchTooExpensive`** cannot trip: `MockMessageGas.messageOverallGasLimit` returns 0, so the accumulated batch gas limit never approaches `MAX_BATCH_GAS`. The guard executes, the branch is unreachable.
  - **`ReentrantBatchCreation`** needs `withBatch` (or `send`) re-entered from inside an adapter's `send` during the dispatch loop, i.e. an adapter mock that calls back into the gateway.
  - Note that the end-to-end suite uses a `MockGateway`, so this suite's number is the protocol's total stateful `Gateway` coverage.
- **Multi-remote.** Only `REMOTE_CENTRIFUGE_ID=2` has adapter sets, so per-cId accounting (two remotes sharing payload hashes, `callCount` and `failedMessages` per cId) is out of reach, and so is a batch spanning two remotes. Multi-pool is covered (see [Pools](#pools)); closing this needs a second remote id with its own adapters and the ghosts' `REMOTE_CENTRIFUGE_ID` reads generalised the way the pool reads were.
- **`AdapterFailover.UnexpectedValue`** (`fromHub` with value) needs the envoy to hold ETH, the same deferral as `NotPayable` above. An unknown `HubCall` kind panics in the enum decode and is not fuzzed.
- **`SimpleAdapter` doesn't model Axelar's pull-based commandId queue.** The Alex-1 target works around this by orchestrating the reconfigure inside the target. A higher-fidelity adapter mock with a `pendingDelivery(hash)` queue surviving reconfigure would let more attack patterns emerge organically.
- **Session-id exhaustion** (`activeSessionId == type(uint16).max`), where `setAdapters` panics `0x11` instead of wrapping and permanently bricks reconfiguration for that (cId, pool). Unreachable in fuzz sequences since `seqLen` 50 is far below 65535, and not modelled here. The DoS shape is a protocol-design question rather than a harness gap.

## Known revert reasons

When a target catches an unexpected revert, check this first.

| Selector | Source | Common cause |
|----------|--------|--------------|
| `IGateway.Paused` | `Gateway.handle/send/retry/repay` (`pauseable` modifier) | `mockProtocolPauser.paused() == true` |
| `IGateway.NotFailedMessage` | `Gateway.retry/clearFailedMessage` | `failedMessages[cId][hash] == 0` |
| `IGateway.CannotBeReceivedLocally` | `Gateway.handle` | `centrifugeId == localCentrifugeId` (forgery guard) |
| `IGateway.MalformedBatch` | `Gateway.handle` | a later message in an inbound batch names a different pool than the first; reaching it through adapters reverts the delivering vote too |
| `IGateway.SourceMismatch` | `Gateway.handle` | message source-restricted via the mock magic `0xFE ++ bytes2(src)` and delivered from a different chain |
| `IGateway.EmptyMessage` / `TooLongMessage` | `Gateway.send` | payload bounds; the `validPayload` modifier prevents this |
| `IMultiAdapter.InvalidAdapter` | `MultiAdapter._resolve` | adapter not configured for the (cId, pool, sessionId-from-payload-prefix): after a reconfigure to a smaller count, on unwrapped or mis-wrapped payloads, or on a blocked session |
| `IMultiAdapter.{ExceedsMax, ThresholdHigherThanQuorum, NoDuplicatesAllowed}` | `MultiAdapter.setAdapters` | exercised by the M6.a/b/d negatives |
| `IMultiAdapter.ZeroThreshold` | `MultiAdapter.setAdapters` | `threshold == 0` with a non-empty adapter set; an empty set with 0 is the legal disable path (M6.e) |
| `IMultiAdapter.UnexpectedSessionId` | `MultiAdapter.setAdapters` | `targetSessionId != nextActiveSessionId(cId, pool)`. Raised BEFORE `_installSession`, so a negative target aiming at `NoDuplicatesAllowed` must pass the correct id or it fails for the wrong reason (M6.f) |
| `IMultiAdapter.SessionNotConfigured` | `MultiAdapter.blockSession` | session never configured, or already blocked with its config stashed (B1) |
| `IMultiAdapter.SessionNotBlocked` | `MultiAdapter.unblockSession` | session not currently blocked (B2) |
| `IAdapterEntrypoint.NotEnoughVotes` | `MultiAdapter.execute` | positive votes below threshold (V2) |
| `IMultiAdapter.EmptyAdapterSet` | `MultiAdapter.send/estimate` | no active adapters for (cId, pool): unconfigured cId, or the active session is blocked (G6) |
| `Auth.NotAuthorized` | `_resolve` / `onlyAuthOrManager` | caller is neither the named adapter, nor a ward, nor a pool manager; for `executeFailover`, the failover lacks the pool's manager role (FO10) |
| `IAdapterFailover.{NoPendingFailover, TimelockNotElapsed, FailoverExpired, ParamsMismatch}` | `AdapterFailover.executeFailover`, checked in that order | nothing armed (never, cancelled, vetoed or executed); before `executableAt`; after `executableAt + timelock`; params other than the armed ones. A negative aiming at a later one must satisfy the earlier ones first |
| `IAdapterFailover.{NotSteward, InvalidThreshold, NotEnvoy}` | `initiateFailover` / `cancelFailover` / `fromHub` | caller not the pool's steward; threshold 0; `fromHub` not from the envoy |

## References

- Source under test: `src/core/messaging/{Gateway,MultiAdapter}.sol`, `src/adapters/StandbyAdapter.sol`, `src/managers/adapters/AdapterFailover.sol`, `src/misc/libraries/ArrayLib.sol`
- Unit tests for the same contracts: `test/core/unit/Gateway.t.sol`, `test/core/unit/MultiAdapter.t.sol`
- Recon framework docs: https://book.getrecon.xyz/writing_invariant_tests/chimera_framework.html
- Recon reproducer scraper: https://getrecon.xyz/tools/echidna
