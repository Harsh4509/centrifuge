// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {BatcherActor} from "./mocks/BatcherActor.sol";
import {TargetFunctions} from "./TargetFunctions.sol";

import {IAuth} from "../../../src/misc/interfaces/IAuth.sol";

import {PoolId} from "../../../src/core/types/PoolId.sol";
import {IAdapter} from "../../../src/core/messaging/interfaces/IAdapter.sol";
import {IGateway} from "../../../src/core/messaging/interfaces/IGateway.sol";
import {IAdapterEntrypoint} from "../../../src/core/messaging/interfaces/IAdapterEntrypoint.sol";
import {IMultiAdapter, MAX_ADAPTER_COUNT} from "../../../src/core/messaging/interfaces/IMultiAdapter.sol";

import {IAdapterFailover} from "../../../src/managers/adapters/interfaces/IAdapterFailover.sol";

import {Test} from "forge-std/Test.sol";

import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {IStandbyAdapter} from "../../../src/adapters/interfaces/IStandbyAdapter.sol";

// forge test --match-contract CryticMessagingToFoundry -vv
contract CryticMessagingToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function test_crytic() public {}

    // ─── Smoke tests ─────────────────────────────────────────────────────────

    function test_deliver_to_threshold_executes_processor() public {
        bytes memory payload = _bucket(abi.encode(uint256(42)));

        this.multiAdapter_deliver(0, payload); // adapter0 votes
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(payload)), 0);

        this.multiAdapter_deliver(1, payload); // adapter1 votes → threshold=2 reached
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(payload)), 1);

        property_M1_threshold_respected();
    }

    function test_duplicate_same_adapter_no_double_execution() public {
        bytes memory payload = _bucket(abi.encode(uint256(99)));

        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(0, payload); // second vote from same adapter — votes[0] = 2, others = 0
        // Only 1 positive slot despite 2 deliveries; threshold=2 needs 2 *different* adapters.
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(payload)), 0);

        property_M1_threshold_respected();
    }

    function test_retry_nonFailed_reverts() public {
        bytes memory message = _bucket(abi.encode(uint256(7)));
        vm.expectRevert(IGateway.NotFailedMessage.selector);
        gateway.retry(REMOTE_CENTRIFUGE_ID, message);
    }

    function test_failed_message_retry_flow() public {
        bytes memory payload = _bucket(abi.encode(uint256(55)));
        bytes32 payloadHash = keccak256(payload);

        gateway_setProcessorFail(payload, true);

        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(1, payload);

        assertGt(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, payloadHash), 0);

        gateway_setProcessorFail(payload, false);
        this.gateway_retry(REMOTE_CENTRIFUGE_ID, payload);

        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, payloadHash), 0);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, payloadHash), 1);
    }

    // ─── G2: Execution conservation ──────────────────────────────────────────

    function test_G2_execution_conservation() public {
        bytes memory payload = _bucket(abi.encode(uint256(100)));
        bytes32 payloadHash = keccak256(payload);

        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(1, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, payloadHash), 1);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, payloadHash), 0);
        property_G2_execution_conservation();

        // After the first execution votes are [0, 0, -1] (decreaseFirstNValues consumed all 3 slots),
        // so adapter2 would need two votes just to turn positive: use adapter0 + adapter1 again.
        gateway_setProcessorFail(payload, true);
        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(1, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, payloadHash), 1);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, payloadHash), 1);
        property_G2_execution_conservation();

        gateway_setProcessorFail(payload, false);
        this.gateway_retry(REMOTE_CENTRIFUGE_ID, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, payloadHash), 2);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, payloadHash), 0);
        property_G2_execution_conservation();
    }

    // ─── M4: Vote sum bounded ────────────────────────────────────────────────

    function test_M4_vote_sum_bounded() public {
        bytes memory payload = _bucket(abi.encode(uint256(200)));

        this.multiAdapter_deliver(0, payload);
        property_M4_vote_sum_bounded();

        this.multiAdapter_deliver(0, payload);
        property_M4_vote_sum_bounded();

        this.multiAdapter_deliver(1, payload);
        property_M4_vote_sum_bounded();
    }

    /// @dev Reading votes by the bare wrapped hash instead of keccak256(poolId ++ wrapped) hits an empty
    ///      slot and fails SILENTLY (M4 vacuous, clean-slate preconditions stop guarding): assert both.
    function test_voteKey_addresses_the_live_tally() public {
        bytes memory payload = _bucket(abi.encode(uint256(0xB01E)));
        PoolId pool = _route(payload);
        bytes memory wrapped = _wrap(payload);

        this.multiAdapter_deliver(0, payload); // one vote, below threshold=2

        int16[MAX_ADAPTER_COUNT] memory viaVoteKey = multiAdapter.votes(REMOTE_CENTRIFUGE_ID, _voteKey(pool, wrapped));
        assertEq(viaVoteKey[0], int16(1), "vote key does not address the live tally");

        int16[MAX_ADAPTER_COUNT] memory viaBareHash = multiAdapter.votes(REMOTE_CENTRIFUGE_ID, keccak256(wrapped));
        assertEq(viaBareHash[0], int16(0), "bare wrapped hash must no longer address any tally");

        // The pool prefix separates them, at uint64 width.
        assertEq(_voteKey(pool, wrapped), keccak256(abi.encodePacked(pool.raw(), wrapped)), "vote key encoding");
    }

    // ─── G5: Pause enforcement ───────────────────────────────────────────────

    /// @dev Pause only blocks gateway.handle(), so vote once, pause, then deliver the second to threshold.
    function test_G5_pause_blocks_inbound() public {
        // Break loudly if Setup.sol's constants change.
        require(THRESHOLD == 2 && ADAPTER_COUNT == 3, "smoke test assumes THRESHOLD=2, ADAPTER_COUNT=3");

        bytes memory payload = _bucket(abi.encode(uint256(300)));

        this.multiAdapter_deliver(0, payload);

        mockProtocolPauser.setPaused(true);

        try adapter1.deliver(_wrap(payload)) {
            assertTrue(false, "G5: deliver succeeded while paused");
        } catch (bytes memory err) {
            assertEq(bytes4(err), IGateway.Paused.selector, "G5: wrong revert (expected Paused)");
        }

        mockProtocolPauser.setPaused(false);
    }

    function test_G5b_pause_blocks_retry() public {
        bytes memory payload = _bucket(abi.encode(uint256(301)));
        bytes32 payloadHash = keccak256(payload);

        gateway_setProcessorFail(payload, true);
        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(1, payload);
        assertGt(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, payloadHash), 0);
        gateway_setProcessorFail(payload, false);

        mockProtocolPauser.setPaused(true);
        vm.expectRevert(IGateway.Paused.selector);
        gateway.retry(REMOTE_CENTRIFUGE_ID, payload);
        mockProtocolPauser.setPaused(false);
    }

    // ─── G6: Outbound block enforcement (blockSession successor) ─────────────

    /// @dev Blocking the active session empties the adapter set so send reverts; unblocking restores it.
    function test_G6_outgoing_block_enforced() public {
        bytes memory message = _bucket(abi.encode(uint256(400)));
        uint16 sid = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);

        multiAdapter.blockSession(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, sid);
        assertTrue(multiAdapter.blockedSession(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, sid));
        vm.expectRevert(IMultiAdapter.EmptyAdapterSet.selector);
        gateway.send(REMOTE_CENTRIFUGE_ID, message, true, address(this));

        multiAdapter.unblockSession(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, sid);
        assertFalse(multiAdapter.blockedSession(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, sid));
        gateway.send(REMOTE_CENTRIFUGE_ID, message, true, address(this)); // works again
    }

    /// @dev A batch retained underpaid while its route's active session is then blocked: repay is refused and the
    ///      batch stays retained, and once the session is unblocked it repays.
    function test_U2_repay_waits_out_a_blocked_session() public {
        bytes memory message = _bucket(abi.encode(uint256(401)));
        bytes32 batchHash = keccak256(message);
        this.gateway_send_underpaid(message);
        uint16 sid = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);

        multiAdapter.blockSession(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, sid);
        this.gateway_repay(message);
        (, uint64 counter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        assertEq(counter, 1, "the refused repay consumed the retained batch");

        multiAdapter.unblockSession(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, sid);
        this.gateway_repay(message);
        (, counter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        assertEq(counter, 0, "the batch was not repaid once the session was unblocked");
    }

    // ─── Adapter reconfiguration ─────────────────────────────────────────────

    function test_reconfigure_invalidates_pending_votes() public {
        bytes memory payload = abi.encodePacked(uint8(3)); // a global-pool bucket
        bytes32 payloadHash = keccak256(payload);

        this.multiAdapter_deliver(0, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, payloadHash), 0);

        // New session, same set and threshold (count=3, threshold=2).
        this.multiAdapter_reconfigure(3, 2);

        // adapter0's old-session vote is invalidated, so this is still below threshold.
        this.multiAdapter_deliver(1, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, payloadHash), 0);

        this.multiAdapter_deliver(0, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, payloadHash), 1);

        property_M1_threshold_respected();
        property_M2_adapter_set_integrity();
        property_M3_threshold_leq_quorum();
    }

    function test_reconfigure_threshold_one() public {
        bytes memory payload = _bucket(abi.encode(uint256(501)));
        bytes32 payloadHash = keccak256(payload);

        // count=1, threshold=1: only adapter0.
        this.multiAdapter_reconfigure(1, 1);

        this.multiAdapter_deliver(0, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, payloadHash), 1);

        property_G2_execution_conservation();
    }

    // ─── C1 / H3 regressions: a reconfigure must not trip the per-session bounds ───

    function test_C1_M1_after_threshold_increase_reconfigure() public {
        bytes memory payload = _bucket(abi.encode(uint256(7)));
        bytes32 h = keccak256(payload);

        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(1, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, h), 1);
        property_M1_threshold_respected();

        this.multiAdapter_reconfigure(3, 3);
        assertEq(uint256(multiAdapter.threshold(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL)), 3);

        // Ghosts cleared on reconfigure, so the property holds vacuously here.
        property_M1_threshold_respected();
    }

    function test_C1_G2_after_threshold_increase_reconfigure() public {
        bytes memory payload = _bucket(abi.encode(uint256(8)));

        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(1, payload);
        this.multiAdapter_reconfigure(3, 3); // count=3, threshold=3
        property_G2_execution_conservation();
    }

    function test_H3_M4_after_partial_then_reconfigure() public {
        bytes memory payload = _bucket(abi.encode(uint256(9)));

        this.multiAdapter_deliver(0, payload);
        property_M4_vote_sum_bounded();

        // Ghosts cleared; old-session votes stay in storage under the old wrapped hash.
        this.multiAdapter_reconfigure(3, 2); // count=3, threshold=2

        property_M4_vote_sum_bounded();

        this.multiAdapter_deliver(0, payload);
        property_M4_vote_sum_bounded();
    }

    // ─── M6: setAdapters error-path negative tests ───────────────────────────
    // Each case reads the target session id into a local BEFORE `vm.expectRevert`; inlining
    // `nextActiveSessionId(...)` would consume the expectation with its staticcall. These test the
    // protocol directly, since the target wrappers end in `require(false)`.

    function test_M6_setAdapters_ExceedsMax() public {
        IAdapter[] memory addrs = new IAdapter[](MAX_ADAPTER_COUNT + 1);
        for (uint8 i; i < MAX_ADAPTER_COUNT + 1; i++) {
            addrs[i] = IAdapter(address(adapter0));
        }
        uint16 next = multiAdapter.nextActiveSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        vm.expectRevert(IMultiAdapter.ExceedsMax.selector);
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, addrs, 1, next);
    }

    function test_M6_setAdapters_ThresholdHigherThanQuorum() public {
        IAdapter[] memory addrs = new IAdapter[](2);
        addrs[0] = IAdapter(address(adapter0));
        addrs[1] = IAdapter(address(adapter1));
        uint16 next = multiAdapter.nextActiveSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        vm.expectRevert(IMultiAdapter.ThresholdHigherThanQuorum.selector);
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, addrs, 3, next); // threshold > quorum
    }

    /// @dev NoDuplicatesAllowed is raised AFTER the targetSessionId check, so the correct next id matters.
    function test_M6_setAdapters_NoDuplicatesAllowed() public {
        IAdapter[] memory addrs = new IAdapter[](2);
        addrs[0] = IAdapter(address(adapter0));
        addrs[1] = IAdapter(address(adapter0)); // duplicate
        uint16 next = multiAdapter.nextActiveSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        vm.expectRevert(IMultiAdapter.NoDuplicatesAllowed.selector);
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, addrs, 1, next);
    }

    /// @dev M6.e – threshold 0 over a non-empty set is rejected; an EMPTY set with 0 is the disable path.
    function test_M6_setAdapters_ZeroThreshold() public {
        IAdapter[] memory addrs = new IAdapter[](2);
        addrs[0] = IAdapter(address(adapter0));
        addrs[1] = IAdapter(address(adapter1));
        uint16 next = multiAdapter.nextActiveSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        vm.expectRevert(IMultiAdapter.ZeroThreshold.selector);
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, addrs, 0, next);

        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, new IAdapter[](0), 0, next);
        assertEq(multiAdapter.quorum(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL), 0);
    }

    /// @dev M6.f — the targetSessionId must equal the pool's next session id, in both directions.
    function test_M6_setAdapters_UnexpectedSessionId() public {
        IAdapter[] memory addrs = new IAdapter[](1);
        addrs[0] = IAdapter(address(adapter0));

        uint16 active = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        uint16 next = multiAdapter.nextActiveSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        assertEq(next, active + 1, "nextActiveSessionId != activeSessionId + 1");

        // Stale: the already-active session.
        vm.expectRevert(IMultiAdapter.UnexpectedSessionId.selector);
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, addrs, 1, active);

        // Leap-ahead: skipping a session.
        vm.expectRevert(IMultiAdapter.UnexpectedSessionId.selector);
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, addrs, 1, next + 1);

        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, addrs, 1, next);
        assertEq(multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL), next);
    }

    // ─── Cross-session invariants (cumulative ghosts) ────────────────────────

    /// @dev M1c — cumulative weighted-execution ledger holds across a reconfigure.
    function test_M1c_holds_across_reconfigure() public {
        bytes memory payload = _bucket(abi.encode(uint256(13)));

        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(1, payload);
        property_M1c_weighted_executions_bounded_by_deliveries();

        // Lower the threshold: count=2, threshold=1.
        this.multiAdapter_reconfigure(2, 1);
        property_M1c_weighted_executions_bounded_by_deliveries();

        this.multiAdapter_deliver(1, payload);
        property_M1c_weighted_executions_bounded_by_deliveries();
    }

    function test_callCount_monotonic() public {
        bytes memory payload = _bucket(abi.encode(uint256(14)));
        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(1, payload);
        property_callCount_monotonic();

        this.multiAdapter_reconfigure(3, 3);
        property_callCount_monotonic();
    }

    function test_oldAdapter_rejects_after_reconfigure() public {
        // count=1, threshold=1: only adapter0 active.
        this.multiAdapter_reconfigure(1, 1);

        bytes memory wrapped = _wrap(abi.encode(uint256(15)));
        vm.expectRevert(IMultiAdapter.InvalidAdapter.selector);
        adapter1.deliver(wrapped);
        vm.expectRevert(IMultiAdapter.InvalidAdapter.selector);
        adapter2.deliver(wrapped);
    }

    // ─── vote()/execute() split (proof-adapter path) ─────────────────────────

    /// @dev vote() accumulates votes without ever executing; a subsequent execute() consumes them.
    function test_vote_then_execute_flow() public {
        bytes memory payload = _bucket(abi.encode(uint256(600)));
        bytes32 hash = keccak256(payload);

        this.multiAdapter_vote(0, payload);
        this.multiAdapter_vote(1, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 0);
        property_M4_vote_sum_bounded();

        this.multiAdapter_execute(0, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 1);

        property_M1_threshold_respected();
        property_G2_execution_conservation();
        property_M1c_weighted_executions_bounded_by_deliveries();
    }

    function test_execute_belowThreshold_reverts() public {
        bytes memory payload = _bucket(abi.encode(uint256(601)));
        this.multiAdapter_vote(0, payload); // 1 vote < threshold 2

        // _wrap() staticcalls multiAdapter, so it must run BEFORE vm.expectRevert.
        bytes memory wrapped = _wrap(payload);
        vm.expectRevert(IAdapterEntrypoint.NotEnoughVotes.selector);
        adapter0.deliverExecute(wrapped);
    }

    // ─── blockSession / unblockSession ───────────────────────────────────────

    /// @dev Blocking a historical session kills stale-sessionId replays whose config is still resolvable.
    function test_blockSession_kills_stale_replay() public {
        bytes memory payload = _bucket(abi.encode(uint256(700)));
        uint16 oldSid = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        bytes memory staleWrapped = _wrap(payload);

        this.multiAdapter_reconfigure(3, 2); // new session; old config stays resolvable

        // Pre-block: the stale delivery still lands as an old-session vote, 1 < threshold 2.
        adapter1.deliver(staleWrapped);

        multiAdapter.blockSession(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, oldSid);

        vm.expectRevert(IMultiAdapter.InvalidAdapter.selector);
        adapter2.deliver(staleWrapped);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(payload)), 0);
    }

    function test_blockSession_unconfigured_reverts() public {
        uint16 active = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        vm.expectRevert(IMultiAdapter.SessionNotConfigured.selector);
        multiAdapter.blockSession(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, active + 1);
    }

    function test_unblockSession_notBlocked_reverts() public {
        uint16 active = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        vm.expectRevert(IMultiAdapter.SessionNotBlocked.selector);
        multiAdapter.unblockSession(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, active);
    }

    // ─── updateManager / manager-driven handle (MA1) ─────────────────────────

    /// @dev An enabled manager can submit for configured adapters and reach quorum alone; revoking cuts it.
    function test_updateManager_manager_delivers_on_behalf() public {
        bytes memory payload = _bucket(abi.encode(uint256(1000)));
        bytes32 hash = keccak256(payload);

        bytes memory wrapped = _wrap(payload);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        managerActor.handleAs(REMOTE_CENTRIFUGE_ID, wrapped, IAdapter(address(adapter0)));

        this.multiAdapter_updateManager(true);
        this.multiAdapter_managerDeliver(0, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 0);
        this.multiAdapter_managerDeliver(1, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 1);

        property_M1_threshold_respected();
        property_G2_execution_conservation();

        this.multiAdapter_updateManager(false);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        managerActor.handleAs(REMOTE_CENTRIFUGE_ID, wrapped, IAdapter(address(adapter0)));
    }

    // ─── clearFailedMessage (G7) ─────────────────────────────────────────────

    /// @dev clearFailedMessage discards a failed instance without executing; it can no longer be retried.
    function test_clearFailedMessage_flow() public {
        bytes memory payload = _bucket(abi.encode(uint256(800)));
        bytes32 hash = keccak256(payload);

        gateway_setProcessorFail(payload, true);
        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(1, payload);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, hash), 1);

        this.gateway_clearFailedMessage(payload);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, hash), 0);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 0);

        vm.expectRevert(IGateway.NotFailedMessage.selector);
        gateway.retry(REMOTE_CENTRIFUGE_ID, payload);

        property_G2_execution_conservation();
        property_G4_failed_messages_bounded();
    }

    // ─── Source-chain enforcement (G8/G9) ────────────────────────────────────

    function test_handle_local_origin_reverts() public {
        vm.expectRevert(IGateway.CannotBeReceivedLocally.selector);
        gateway.handle(LOCAL_CENTRIFUGE_ID, abi.encode(uint256(900)));
    }

    /// @dev A source-restricted message (magic 0xFE ++ bytes2(source)) is rejected from the wrong chain.
    function test_handle_source_enforcement() public {
        bytes memory restrictedWrong = abi.encodePacked(bytes1(0xFE), LOCAL_CENTRIFUGE_ID, uint256(901));
        vm.expectRevert(IGateway.SourceMismatch.selector);
        gateway.handle(REMOTE_CENTRIFUGE_ID, restrictedWrong);

        bytes memory restrictedRight = abi.encodePacked(bytes1(0xFE), REMOTE_CENTRIFUGE_ID, uint256(901));
        gateway.handle(REMOTE_CENTRIFUGE_ID, restrictedRight);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(restrictedRight)), 1);
    }

    // ─── §4.1: cross-session retry must not trip per-session bounds ──────────

    /// @dev Retrying a failure funded in a PREVIOUS session (per-session ghosts wiped) yields a callCount
    ///      delta with no matching deliveries; `gateway_retry` bumps the baseline to keep M1/G2 sound.
    function test_M1_G2_cross_session_retry_no_false_positive() public {
        bytes memory payload = _bucket(abi.encode(uint256(1100)));
        bytes32 hash = keccak256(payload);

        gateway_setProcessorFail(payload, true);
        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(1, payload);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, hash), 1);
        gateway_setProcessorFail(payload, false);

        // Reconfigure: per-session ghosts wiped, the funding deliveries forgotten.
        this.multiAdapter_reconfigure(3, 2);

        this.multiAdapter_deliver(0, payload);
        this.gateway_retry(REMOTE_CENTRIFUGE_ID, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 1);

        property_M1_threshold_respected();
        property_G2_execution_conservation();
        property_M1c_weighted_executions_bounded_by_deliveries();
    }

    // ─── S1/S2: outbound fan-out observability ───────────────────────────────

    /// @dev Send fan-out hits every active adapter exactly once with the session-wrapped payload.
    function test_send_fanout_hits_all_active_adapters_wrapped() public {
        bytes memory message = _bucket(abi.encode(uint256(1200)));

        this.gateway_send(REMOTE_CENTRIFUGE_ID, message); // asserts S1/S2 inline
        assertEq(adapter0.sendCount(), 1);
        assertEq(adapter1.sendCount(), 1);
        assertEq(adapter2.sendCount(), 1);
        assertEq(adapter0.lastSentPayloadHash(), keccak256(_wrap(message)));

        // Shrink to [adapter0]: only the active adapter is hit.
        this.multiAdapter_reconfigure(1, 1);
        this.gateway_send(REMOTE_CENTRIFUGE_ID, message);
        assertEq(adapter0.sendCount(), 2);
        assertEq(adapter1.sendCount(), 1);
        assertEq(adapter2.sendCount(), 1);
        assertEq(adapter0.lastSentPayloadHash(), keccak256(_wrap(message))); // new session prefix
    }

    // ─── Alex-1 cross-session replay regression ──────────────────────────────

    /// @dev Cross-session replay must not re-execute: stale bytes count under the old session's threshold.
    function test_alex1_replay_does_not_reexecute() public {
        bytes memory payload = _bucket(abi.encode(uint256(0xa1ec1)));
        // keepIdx=0: adapter0 stays in the post-reconfigure single-adapter set and replays.
        this.multiAdapter_alex1_replay_must_not_execute(0, payload);
    }

    /// @dev Old-session votes ([2,0,0] here) live under a hash M4 never reads after the reconfigure.
    function test_property_M4_no_stale_vote_pollution_across_reconfigure() public {
        bytes memory payload = abi.encodePacked(uint8(4)); // a global-pool bucket
        this.multiAdapter_deliver(0, payload);
        this.multiAdapter_deliver(0, payload); // same adapter twice — below threshold, votes [2,0,0]
        this.multiAdapter_reconfigure(0, 0); // count=1, threshold=1 → new session
        this.multiAdapter_deliver(0, payload); // executes immediately under the new session
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(payload)), 1);
        property_M4_vote_sum_bounded();
    }

    /// @dev A retry re-execution must not be credited at the CURRENT threshold: when the threshold rises
    ///      between the failing delivery and the retry, that would push weighted above cumDeliveries.
    function test_property_M1c_cross_session_retry_threshold_increase() public {
        bytes memory payload = _bucket(abi.encode(uint256(0xdead)));
        bytes32 h = keccak256(payload);

        this.multiAdapter_reconfigure(0, 0); // count=1, threshold=1

        // A SINGLE delivery funds this failure: cumDeliveries=1, weighted=0.
        gateway_setProcessorFail(payload, true);
        this.multiAdapter_deliver(0, payload);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, h), 1);

        this.multiAdapter_reconfigure(3, 2); // count=3, threshold=2

        // Retry re-executes the message without casting a new vote.
        gateway_setProcessorFail(payload, false);
        this.gateway_retry(REMOTE_CENTRIFUGE_ID, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, h), 1);

        // The fail at threshold 1 was credited weighted=1; the retry credits nothing, matching cumDeliveries.
        property_M1c_weighted_executions_bounded_by_deliveries();
    }

    // ─── Outbound batching (BT1-BT7) ───────────────────────────────────────────

    /// @dev The batching contract: the messages inside one batch produce one dispatch per routed pool per active
    /// adapter, carrying the concatenation, so 3 messages over 2 pools dispatch twice. Without batching this
    /// would be 3 dispatches.
    /// forge test --match-test test_withBatch_coalesces_into_one_dispatch -vvv
    function test_withBatch_coalesces_into_one_dispatch() public {
        uint256 before0 = adapter0.sendCount();
        uint256 before1 = adapter1.sendCount();

        // countSeed 3 is inside [1, 3], so `between` keeps it and the batch holds 3 messages (see _batchMessages).
        bytes memory payload = abi.encode(uint256(7));
        bytes[] memory messages = _batchMessages(3, payload);
        assertEq(messages.length, 3, "the batch must hold three messages");
        uint256 pools = _distinctPools(messages);
        assertLt(pools, messages.length, "the messages must share a pool, or nothing can coalesce");

        this.gateway_withBatch(3, payload);

        assertEq(adapter0.sendCount(), before0 + pools, "adapter0 should see one dispatch per pool");
        assertEq(adapter1.sendCount(), before1 + pools, "adapter1 should see one dispatch per pool");
        assertFalse(gateway.isBatching(), "isBatching must be false after withBatch");
        property_G1_isBatching_false();
    }

    function _distinctPools(bytes[] memory messages) internal view returns (uint256 distinct) {
        PoolId[] memory seen = new PoolId[](messages.length);
        for (uint256 i; i < messages.length; i++) {
            PoolId pool = _route(messages[i]);
            bool known;
            for (uint256 j; j < distinct; j++) {
                if (seen[j] == pool) known = true;
            }
            if (!known) seen[distinct++] = pool;
        }
    }

    /// @dev Contrast case pinning that the coalescing above is real: 3 UNBATCHED sends dispatch 3 times.
    /// forge test --match-test test_unbatched_sends_dispatch_individually -vvv
    function test_unbatched_sends_dispatch_individually() public {
        uint256 before0 = adapter0.sendCount();

        // Seed must NOT be a multiple of 16, or gateway_send takes its dead-route escape (EmptyAdapterSet).
        this.gateway_send(1, abi.encode(uint256(1)));
        this.gateway_send(1, abi.encode(uint256(2)));
        this.gateway_send(1, abi.encode(uint256(3)));

        assertEq(adapter0.sendCount(), before0 + 3, "unbatched sends must dispatch once each");
    }

    /// forge test --match-test test_withBatch_explicitValue_overload -vvv
    function test_withBatch_explicitValue_overload() public {
        uint256 before0 = adapter0.sendCount();
        this.gateway_withBatch_explicitValue(1, abi.encode(uint256(11)));
        assertEq(adapter0.sendCount(), before0 + 1);
    }

    /// @dev Only the OUTERMOST withBatch settles: nesting appends and still dispatches once.
    /// forge test --match-test test_withBatch_nested_dispatches_once -vvv
    function test_withBatch_nested_dispatches_once() public {
        uint256 before0 = adapter0.sendCount();
        this.gateway_withBatch_nested(0, abi.encode(uint256(21)));
        assertEq(adapter0.sendCount(), before0 + 1, "nested batch must still be one dispatch");
        assertFalse(gateway.isBatching());
    }

    /// @dev Negative targets end with `require(false)`, so they revert by construction. Asserting on that
    /// revert confirms the body ran to completion: an internal assertion failure would surface a
    /// different reason. See the `statelessTest`-style note in the README.
    /// forge test --match-test test_withBatch_negatives_hold -vvv
    function test_withBatch_negatives_hold() public {
        bytes memory payload = abi.encode(uint256(31));

        vm.expectRevert(bytes(""));
        this.gateway_withBatch_noLock_mustRevert(payload);

        vm.expectRevert(bytes(""));
        this.gateway_withBatch_foreignLock_mustRevert(payload);

        vm.expectRevert(bytes(""));
        this.gateway_withBatch_emptyRevert_mustRevert(payload);

        vm.expectRevert(bytes(""));
        this.gateway_lockCallback_outsideBatch_mustRevert();
    }

    /// @dev The negatives above revert wholesale, so pin each protocol error directly too.
    /// forge test --match-test test_withBatch_revert_reasons -vvv
    function test_withBatch_revert_reasons() public {
        bytes[] memory one = new bytes[](1);
        one[0] = _bucket(abi.encode(uint256(41)));

        vm.expectRevert(IGateway.CallbackWasNotLocked.selector);
        batcher.startBatch(REMOTE_CENTRIFUGE_ID, one, BatcherActor.Mode.SkipLock, address(batcher));

        vm.expectRevert(IGateway.CallbackWasNotFromSender.selector);
        batcher.startBatch(REMOTE_CENTRIFUGE_ID, one, BatcherActor.Mode.ForeignLock, address(batcher));

        vm.expectRevert(IGateway.CallFailedWithEmptyRevert.selector);
        batcher.startBatch(REMOTE_CENTRIFUGE_ID, one, BatcherActor.Mode.EmptyRevert, address(batcher));

        vm.expectRevert(IGateway.CallbackIsLocked.selector);
        gateway.lockCallback();
    }

    // ─── Underpaid batch / repay (U1-U5) ─────────────────────────────────────

    /// @dev A non-zero quote with zero fuel retains the batch instead of dispatching it; dropping the
    /// quote lets repay settle it. Pins that the retention is real: no dispatch happens on the send.
    /// forge test --match-test test_underpaid_send_retains_then_repay_settles -vvv
    function test_underpaid_send_retains_then_repay_settles() public {
        bytes memory payload = _bucket(abi.encode(uint256(77)));
        bytes32 batchHash = keccak256(payload);
        uint256 before0 = adapter0.sendCount();

        this.shortcut_gateway_repay_underpaid(payload);

        // Net effect: exactly one dispatch, and the underpaid entry is fully consumed and deleted.
        assertEq(adapter0.sendCount(), before0 + 1, "repay should dispatch exactly once");
        (uint128 gasLimit, uint64 counter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        assertEq(counter, 0, "underpaid counter should be consumed");
        assertEq(gasLimit, 0, "underpaid entry should be deleted at counter 0");

        property_adapterEstimate_zero_between_txs();
    }

    /// @dev The retention step in isolation: a quoted send with no fuel must NOT reach the adapter.
    /// forge test --match-test test_underpaid_send_does_not_dispatch -vvv
    function test_underpaid_send_does_not_dispatch() public {
        bytes memory payload = _bucket(abi.encode(uint256(78)));
        uint256 before0 = adapter0.sendCount();

        adapter0.setEstimate(1);
        adapter1.setEstimate(1);
        adapter2.setEstimate(1);

        gateway.send(REMOTE_CENTRIFUGE_ID, payload, true, address(this));

        assertEq(adapter0.sendCount(), before0, "an underpaid send must not dispatch");
        (, uint64 counter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, keccak256(payload));
        assertEq(counter, 1, "the batch should be retained as underpaid");
    }

    /// @dev Repaying twice must fail: the second call finds a consumed counter.
    /// forge test --match-test test_repay_twice_reverts -vvv
    function test_repay_twice_reverts() public {
        bytes memory payload = _bucket(abi.encode(uint256(79)));
        this.shortcut_gateway_repay_underpaid(payload);

        vm.expectRevert(IGateway.NotUnderpaidBatch.selector);
        gateway.repay(REMOTE_CENTRIFUGE_ID, payload, address(this));
    }

    /// forge test --match-test test_underpaid_negatives_hold -vvv
    function test_underpaid_negatives_hold() public {
        bytes memory payload = abi.encode(uint256(80));

        vm.expectRevert(bytes(""));
        this.gateway_send_notEnoughGas_mustRevert(payload);

        vm.expectRevert(bytes(""));
        this.gateway_repay_nonUnderpaid_mustRevert(payload);

        // The quote must be back to zero after those handlers rolled back.
        property_adapterEstimate_zero_between_txs();
    }

    /// @dev Pins the NotEnoughGas branch directly: quoted cost, zero fuel, unpaidMode off.
    /// forge test --match-test test_send_notEnoughGas_reason -vvv
    function test_send_notEnoughGas_reason() public {
        adapter0.setEstimate(1);
        adapter1.setEstimate(1);
        adapter2.setEstimate(1);

        vm.expectRevert(IGateway.NotEnoughGas.selector);
        gateway.send(REMOTE_CENTRIFUGE_ID, abi.encode(uint256(81)), false, address(this));
    }

    /// @dev The point of the split: a retained batch must survive to the NEXT transaction, and the ledger
    /// must track it. This is the state the atomic shortcut can never produce.
    /// forge test --match-test test_underpaid_batch_persists_across_transactions -vvv
    function test_underpaid_batch_persists_across_transactions() public {
        bytes memory payload = _bucket(abi.encode(uint256(90)));
        bytes32 batchHash = keccak256(payload);

        this.gateway_send_underpaid(payload);

        // Outstanding BETWEEN transactions, which is what the fuzzer can now interleave against.
        (, uint64 counter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        assertEq(counter, 1, "batch must stay outstanding after the send transaction");
        property_U6_underpaid_ledger_matches();
        property_adapterEstimate_zero_between_txs();

        this.gateway_repay(payload);

        (, uint64 after_) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        assertEq(after_, 0, "repay should consume the outstanding instance");
        property_U6_underpaid_ledger_matches();
    }

    /// @dev A reconfigure between retention and settlement must not strand or duplicate the batch:
    /// `Gateway.underpaid` is keyed by (cId, batchHash) with no session component.
    /// forge test --match-test test_underpaid_survives_reconfigure -vvv
    function test_underpaid_survives_reconfigure() public {
        bytes memory payload = _bucket(abi.encode(uint256(91)));
        bytes32 batchHash = keccak256(payload);

        this.gateway_send_underpaid(payload);
        this.multiAdapter_reconfigure(0, 0); // count=1, threshold=1, new session

        (, uint64 counter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        assertEq(counter, 1, "a reconfigure must not clear an outstanding unpaid batch");
        property_U6_underpaid_ledger_matches();

        this.gateway_repay(payload); // still settleable under the new adapter set
        property_U6_underpaid_ledger_matches();
    }

    /// @dev Two retentions of the same bucketed payload must stack, and each repay consumes exactly one.
    /// forge test --match-test test_underpaid_instances_stack -vvv
    function test_underpaid_instances_stack() public {
        bytes memory payload = _bucket(abi.encode(uint256(92)));
        bytes32 batchHash = keccak256(payload);

        this.gateway_send_underpaid(payload);
        this.gateway_send_underpaid(payload);

        (, uint64 counter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        assertEq(counter, 2, "instances should stack");
        property_U6_underpaid_ledger_matches();

        this.gateway_repay(payload);
        (, uint64 mid) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        assertEq(mid, 1, "one repay consumes exactly one instance");
        property_U6_underpaid_ledger_matches();
    }

    // ─── Gateway admin (updateManager, file) ─────────────────────────────────

    /// forge test --match-test test_gateway_updateManager_round_trip -vvv
    function test_gateway_updateManager_round_trip() public {
        assertFalse(gateway.manager(GLOBAL_POOL, address(managerActor)), "should start without the role");

        this.gateway_updateManager(true);
        assertTrue(gateway.manager(GLOBAL_POOL, address(managerActor)), "grant should stick");

        this.gateway_updateManager(false);
        assertFalse(gateway.manager(GLOBAL_POOL, address(managerActor)), "revoke should stick");
    }

    /// forge test --match-test test_gateway_file_unrecognized_reverts -vvv
    function test_gateway_file_unrecognized_reverts() public {
        vm.expectRevert(IGateway.FileUnrecognizedParam.selector);
        gateway.file("notAParam", address(mockMessageGas));

        // The handler wraps that in a selector-checked catch and then rolls back.
        vm.expectRevert(bytes(""));
        this.gateway_file_unrecognizedParam_mustRevert("notAParam");
    }

    /// forge test --match-test test_multiAdapter_file_unrecognized_reverts -vvv
    function test_multiAdapter_file_unrecognized_reverts() public {
        vm.expectRevert(IMultiAdapter.FileUnrecognizedParam.selector);
        multiAdapter.file("notAParam", address(mockMessageGas));

        vm.expectRevert(bytes(""));
        this.multiAdapter_file_unrecognizedParam_mustRevert("notAParam");
    }

    // ─── Gateway pool manager (quorum bypass) ────────────────────────────────

    /// @dev Manager-submitted executions and failures interleaved with quorum deliveries of the SAME
    ///      tracked payload: every delivery-bound property must keep holding, and a manager-injected
    ///      failure must stay retryable and clearable like a quorum-driven one.
    /// forge test --match-test test_gateway_manager_handle_absorbed_by_ghosts -vvv
    function test_gateway_manager_handle_absorbed_by_ghosts() public {
        bytes memory payload = abi.encodePacked(uint8(2)); // a global-pool bucket
        bytes32 hash = keccak256(payload);
        this.gateway_updateManager(true);

        this.multiAdapter_deliver(0, payload); // tracked, below threshold
        this.gateway_managerHandle(payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 1, "manager executed");
        _assertDeliveryBoundsHold();

        this.multiAdapter_deliver(1, payload); // quorum reached
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 2, "quorum executed");
        _assertDeliveryBoundsHold();

        gateway_setProcessorFail(payload, true);
        this.gateway_managerHandle(payload);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, hash), 1, "manager failure recorded");
        _assertDeliveryBoundsHold();

        gateway_setProcessorFail(payload, false);
        this.gateway_retry(REMOTE_CENTRIFUGE_ID, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 3, "manager failure retried");
        _assertDeliveryBoundsHold();

        gateway_setProcessorFail(payload, true);
        this.gateway_managerHandle(payload);
        this.gateway_managerClearFailedMessage(payload);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, hash), 0, "manager cleared its failure");
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 3, "clear did not execute");
        _assertDeliveryBoundsHold();
    }

    /// @dev Contrast for the test above: the same vote-free execution NOT absorbed by the handler is a
    ///      callCount delta with no matching deliveries, which M1 reports. Pins the absorption as load-bearing.
    /// forge test --match-test test_unabsorbed_direct_handle_trips_M1 -vvv
    function test_unabsorbed_direct_handle_trips_M1() public {
        bytes memory payload = _bucket(abi.encode(uint256(951)));
        this.multiAdapter_deliver(0, payload);

        gateway.handle(REMOTE_CENTRIFUGE_ID, payload); // the ward, outside any handler

        vm.expectRevert(bytes("M1: callCount * threshold > deliveries: 2 > 1"));
        this.property_M1_threshold_respected();
    }

    /// forge test --match-test test_gateway_manager_role_gates_handle_and_clear -vvv
    function test_gateway_manager_role_gates_handle_and_clear() public {
        bytes memory payload = _bucket(abi.encode(uint256(952)));

        // The MultiAdapter manager role does not open the gateway.
        this.multiAdapter_updateManager(true);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        managerActor.gatewayHandle(REMOTE_CENTRIFUGE_ID, payload);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        managerActor.gatewayClearFailedMessage(REMOTE_CENTRIFUGE_ID, payload);

        vm.expectRevert(bytes(""));
        this.gateway_managerHandle_notManager_mustRevert(payload);
        vm.expectRevert(bytes(""));
        this.gateway_managerClearFailedMessage_notManager_mustRevert(payload);

        this.gateway_updateManager(true);
        this.gateway_managerHandle(payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(payload)), 1);
    }

    /// @dev A MultiAdapter manager's vote stands in for the named adapter's: two manager votes reach
    ///      quorum, and the manager's execute consumes them. Without the role both overloads revert.
    /// forge test --match-test test_multiAdapter_manager_vote_execute -vvv
    function test_multiAdapter_manager_vote_execute() public {
        bytes memory payload = _bucket(abi.encode(uint256(953)));
        bytes32 hash = keccak256(payload);

        vm.expectRevert(bytes(""));
        this.multiAdapter_managerVoteExecute_notManager_mustRevert(false, payload);
        vm.expectRevert(bytes(""));
        this.multiAdapter_managerVoteExecute_notManager_mustRevert(true, payload);

        this.multiAdapter_updateManager(true);
        this.multiAdapter_managerVote(0, payload);
        this.multiAdapter_managerVote(1, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 0, "vote alone never executes");

        this.multiAdapter_managerExecute(2, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 1, "manager execute consumed quorum");
        _assertDeliveryBoundsHold();
    }

    // ─── Multiple pools ──────────────────────────────────────────────────────

    /// @dev POOL_B's `SetPoolAdapters` travels over the global set until POOL_B is configured. The global
    ///      vote cast before that and a POOL_B vote after it are on identical wrapped bytes (both sessions
    ///      are 1), so only the pool prefix of the vote key keeps them in separate tallies. One POOL_B vote
    ///      must not execute at threshold 2.
    /// forge test --match-test test_fallback_votes_stay_in_the_global_tally -vvv
    function test_fallback_votes_stay_in_the_global_tally() public {
        bytes memory payload = abi.encodePacked(countingProcessor.SET_POOL_B());
        bytes32 hash = keccak256(payload);
        assertTrue(_route(payload) == GLOBAL_POOL, "travels over the global set while POOL_B is unconfigured");
        bytes memory globalWrapped = _wrap(payload);

        this.multiAdapter_deliver(0, payload); // one global vote, below threshold
        this.multiAdapter_reconfigurePool(2, 3, 2); // POOL_B's first configuration: 3 adapters, threshold 2
        assertTrue(_route(payload) == POOL_B, "routes over POOL_B's own set once configured");
        assertEq(keccak256(_wrap(payload)), keccak256(globalWrapped), "same wrapped bytes in both pools");

        this.multiAdapter_deliver(1, payload); // first POOL_B vote
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 0, "global vote counted toward POOL_B");
        _assertDeliveryBoundsHold();

        this.multiAdapter_deliver(2, payload); // second POOL_B vote reaches POOL_B's threshold
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, hash), 1, "POOL_B quorum executed");
        _assertDeliveryBoundsHold();
    }

    /// @dev One batch naming the global pool, POOL_A and (via fallback) POOL_B fills three gateway slots, so
    ///      it dispatches three times, each through its routed set: every adapter is sent each batch once.
    /// forge test --match-test test_multi_pool_batch_dispatches_once_per_pool -vvv
    function test_multi_pool_batch_dispatches_once_per_pool() public {
        bytes[] memory messages = new bytes[](4);
        messages[0] = abi.encodePacked(uint8(1)); // global
        messages[1] = abi.encodePacked(uint8(11)); // POOL_A
        messages[2] = abi.encodePacked(countingProcessor.SET_POOL_B()); // POOL_B, over the global set
        messages[3] = abi.encodePacked(uint8(12)); // POOL_A again: appended to its slot

        (Dispatch[] memory planned, uint256[3] memory sendsBefore) = _planDispatches(messages);
        assertEq(planned.length, 3, "one dispatch per pool named");

        batcher.startBatch(REMOTE_CENTRIFUGE_ID, messages, BatcherActor.Mode.Normal, address(batcher));

        _assertDispatched(planned, sendsBefore);
        assertEq(adapter0.sendCount(), sendsBefore[0] + 3, "shared adapter dispatched once per pool");
        assertEq(
            adapter0.sentCount(keccak256(abi.encodePacked(uint16(1), uint8(11), uint8(12)))),
            1,
            "POOL_A's two messages coalesced into one dispatch"
        );
    }

    /// @dev Manager roles are per pool: MultiAdapter checks the routed pool, the gateway the pool the
    ///      message names. A fallback payload therefore needs the global MultiAdapter role but the POOL_B
    ///      gateway role.
    /// forge test --match-test test_manager_roles_are_pool_scoped -vvv
    function test_manager_roles_are_pool_scoped() public {
        bytes memory globalPayload = abi.encodePacked(uint8(1));
        bytes memory poolAPayload = abi.encodePacked(uint8(11));
        bytes memory fallbackPayload = abi.encodePacked(countingProcessor.SET_POOL_B());

        this.multiAdapter_updateManagerPool(1, true); // POOL_A only
        this.multiAdapter_managerDeliver(0, poolAPayload);
        vm.expectRevert(bytes("")); // MA1 holds for the global payload
        this.multiAdapter_managerHandle_notManager_mustRevert(globalPayload);
        IAdapter[] memory globalSet = _activeList(GLOBAL_POOL);
        bytes memory wrapped = _wrap(globalPayload);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        managerActor.handleAs(REMOTE_CENTRIFUGE_ID, wrapped, globalSet[0]);

        this.gateway_updateManagerPool(0, true); // global gateway role does not cover the fallback
        vm.expectRevert(IAuth.NotAuthorized.selector);
        managerActor.gatewayHandle(REMOTE_CENTRIFUGE_ID, fallbackPayload);

        this.gateway_updateManagerPool(2, true);
        this.gateway_managerHandle(fallbackPayload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(fallbackPayload)), 1);
        _assertDeliveryBoundsHold();
    }

    /// @dev Reconfiguring one pool resets only that pool's per-session entries: a POOL_A entry survives a
    ///      global reconfigure and keeps bounding POOL_A's executions.
    /// forge test --match-test test_reconfigure_clears_only_its_pool -vvv
    function test_reconfigure_clears_only_its_pool() public {
        bytes memory globalPayload = abi.encodePacked(uint8(1));
        bytes memory poolAPayload = abi.encodePacked(uint8(11));
        this.multiAdapter_deliver(0, globalPayload);
        this.multiAdapter_deliver(0, poolAPayload);

        this.multiAdapter_reconfigure(3, 3); // global: 3 adapters, threshold 3

        assertFalse(ghost_isTracked[REMOTE_CENTRIFUGE_ID][GLOBAL_POOL][keccak256(globalPayload)], "global entry");
        assertTrue(ghost_isTracked[REMOTE_CENTRIFUGE_ID][POOL_A][keccak256(poolAPayload)], "POOL_A entry");
        assertEq(ghost_deliveries[REMOTE_CENTRIFUGE_ID][POOL_A][keccak256(poolAPayload)], 1);

        this.multiAdapter_deliver(1, poolAPayload); // POOL_A still at threshold 2
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(poolAPayload)), 1);
        _assertDeliveryBoundsHold();
    }

    /// @dev Messages longer than a transient chunk: each append crosses 32-byte boundaries, and the dispatch must
    ///      still be the exact concatenation.
    /// forge test --match-test test_long_message_batch_spans_transient_chunks -vvv
    function test_long_message_batch_spans_transient_chunks() public {
        bytes memory payload = new bytes(70);
        for (uint256 i; i < payload.length; i++) {
            payload[i] = bytes1(uint8(i + 1));
        }
        uint256 before = adapter0.sendCount();

        this.gateway_withBatch_longMessages(3, payload);

        assertGt(adapter0.sendCount(), before, "dispatched");
    }

    // ─── Multi-message inbound batches ───────────────────────────────────────

    /// @dev Votes are cast on the whole batch; at quorum each message is processed on its own, a repeated
    ///      message once per occurrence.
    /// forge test --match-test test_batch_processes_each_message_per_occurrence -vvv
    function test_batch_processes_each_message_per_occurrence() public {
        bytes memory batch = abi.encodePacked(uint8(1), uint8(2), uint8(1));
        bytes memory wrapped = _wrap(batch);

        adapter0.deliver(wrapped);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(abi.encodePacked(uint8(1)))), 0);

        adapter1.deliver(wrapped);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(abi.encodePacked(uint8(1)))), 2);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(abi.encodePacked(uint8(2)))), 1);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(batch)), 0, "batch is not a message");
    }

    /// @dev One failing message is recorded on its own and stays retryable; the rest of the batch executes.
    /// forge test --match-test test_batch_failure_is_per_message -vvv
    function test_batch_failure_is_per_message() public {
        bytes memory failing = abi.encodePacked(uint8(4));
        bytes memory ok = abi.encodePacked(uint8(5));
        gateway_setProcessorFail(failing, true);

        bytes memory wrapped = _wrap(abi.encodePacked(failing, ok));
        adapter0.deliver(wrapped);
        adapter1.deliver(wrapped);

        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, keccak256(failing)), 1);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(ok)), 1);

        gateway_setProcessorFail(failing, false);
        gateway.retry(REMOTE_CENTRIFUGE_ID, failing);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(failing)), 1);
    }

    /// forge test --match-test test_mixed_pool_batch_reverts -vvv
    function test_mixed_pool_batch_reverts() public {
        bytes memory globalMessage = abi.encodePacked(uint8(1));
        bytes memory poolAMessage = abi.encodePacked(uint8(11));

        vm.expectRevert(IGateway.MalformedBatch.selector);
        gateway.handle(REMOTE_CENTRIFUGE_ID, abi.encodePacked(globalMessage, poolAMessage));

        // The handler wraps that in a selector-checked catch and then rolls back.
        vm.expectRevert(bytes(""));
        this.gateway_handle_mixedPoolBatch_mustRevert(globalMessage, poolAMessage);
    }

    /// @dev Through the handler: two adapters' batch deliveries reach quorum, G12 holds inline, and the
    ///      per-message delivery credit keeps every bound.
    /// forge test --match-test test_deliverBatch_handler_keeps_bounds -vvv
    function test_deliverBatch_handler_keeps_bounds() public {
        bytes memory payload = abi.encode(uint256(960));

        this.multiAdapter_deliverBatch(0, 3, payload);
        _assertDeliveryBoundsHold();
        this.multiAdapter_deliverBatch(1, 3, payload);
        _assertDeliveryBoundsHold();

        assertGt(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(_bucket(payload))), 0, "batch executed");
    }

    // ─── StandbyAdapter ──────────────────────────────────────────────────────

    /// @dev A send through a set holding the standby credits it instead of dispatching; one forward consumes
    ///      the credit and relays the same bytes through the underlying, and a second forward finds none.
    /// forge test --match-test test_standby_credit_then_forward -vvv
    function test_standby_credit_then_forward() public {
        this.multiAdapter_reconfigureWithStandby(0, 2); // global: [adapter0, adapter1, standby], 2-of-3
        bytes memory message = abi.encodePacked(uint8(1));
        bytes memory wrapped = _wrap(message);

        this.gateway_send(REMOTE_CENTRIFUGE_ID, message);
        assertEq(standby.forwardable(_standbyId(wrapped)), 1, "credited, not dispatched");
        assertEq(underlying.sendCount(), 0, "nothing relayed yet");
        property_SB1_standby_credit_ledger();

        this.standby_forward(0);
        assertEq(standby.forwardable(_standbyId(wrapped)), 0);
        assertEq(underlying.lastSentPayloadHash(), keccak256(wrapped));
        property_SB1_standby_credit_ledger();

        vm.expectRevert(bytes(""));
        this.standby_forward_uncredited_mustRevert(wrapped);
    }

    /// @dev The standby's inbound vote arrives through the underlying and counts like any adapter's: one simple
    ///      adapter plus the standby reach a 2-of-3 quorum.
    /// forge test --match-test test_standby_vote_counts_toward_quorum -vvv
    function test_standby_vote_counts_toward_quorum() public {
        this.multiAdapter_reconfigureWithStandby(0, 2);
        bytes memory payload = abi.encodePacked(uint8(2));

        this.multiAdapter_deliver(0, payload); // adapter0
        this.multiAdapter_deliver(2, payload); // the standby, via its underlying
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(payload)), 1);
        _assertDeliveryBoundsHold();
    }

    /// forge test --match-test test_standby_negatives -vvv
    function test_standby_negatives() public {
        this.multiAdapter_reconfigureWithStandby(0, 2);
        this.gateway_send(REMOTE_CENTRIFUGE_ID, abi.encodePacked(uint8(1)));

        // Each handler hits its expected revert, then rolls back with require(false).
        vm.expectRevert(bytes(""));
        this.standby_forward_wrongGas_mustRevert(0, 1);
        vm.expectRevert(bytes(""));
        this.standby_forward_underpaid_mustRevert(0);
        vm.expectRevert(bytes(""));
        this.standby_send_notEntrypoint_mustRevert(abi.encodePacked(uint8(1)));
        for (uint8 kind; kind < 3; kind++) {
            vm.expectRevert(bytes(""));
            this.standby_inbound_notUnderlying_mustRevert(kind, abi.encodePacked(uint8(1)));
        }

        vm.expectRevert(IAdapter.NotEntrypoint.selector);
        standby.send(REMOTE_CENTRIFUGE_ID, abi.encodePacked(uint8(1)), DISPATCH_GAS_LIMIT, address(this));
        bytes memory wrapped = _wrap(abi.encodePacked(uint8(1)));
        vm.expectRevert(IStandbyAdapter.NotForwardable.selector);
        standby.forward(REMOTE_CENTRIFUGE_ID, wrapped, 1);
    }

    /// @dev Blocking the active session of a retained batch's pool makes repay revert `EmptyAdapterSet` by design;
    ///      `gateway_repay` must check that the refused repay kept the batch, not report U2, and the batch settles
    ///      after an unblock.
    /// forge test --match-test test_repay_skips_blocked_session_then_settles -vvv
    function test_repay_skips_blocked_session_then_settles() public {
        bytes memory payload = hex"00";
        this.gateway_send_underpaid(payload);
        this.multiAdapter_blockSession(1, payload);

        this.gateway_repay(payload);
        property_U6_underpaid_ledger_matches();

        this.multiAdapter_unblockSession(1); // the global pool, where hex"00" routes
        this.gateway_repay(payload);
        property_U6_underpaid_ledger_matches();
    }

    /// @dev A standby-only set has no unpaid branch: its estimate is pure 0, so a send cannot be underpaid. The
    ///      underpaid handlers must stop at their precondition instead of reporting U1/U4/U7.
    /// forge test --match-test test_standby_only_set_skips_underpaid_handlers -vvv
    function test_standby_only_set_skips_underpaid_handlers() public {
        this.multiAdapter_reconfigureWithStandby(0, 2);
        this.multiAdapter_alex1_replay_must_not_execute(2, hex"00");
        IAdapter[] memory list = _activeList(GLOBAL_POOL);
        assertEq(list.length, 1);
        assertEq(address(list[0]), address(standby), "only the standby left");

        // Under Foundry a failed precondition is a vm.assume rejection.
        vm.expectRevert(bytes("FOUNDRY::ASSUME"));
        this.gateway_send_underpaid(hex"00");
        vm.expectRevert(bytes("FOUNDRY::ASSUME"));
        this.gateway_send_notEnoughGas_mustRevert(hex"00");
        vm.expectRevert(bytes("FOUNDRY::ASSUME"));
        this.shortcut_gateway_repay_underpaid(hex"8b");

        // The send itself is fine: it credits the standby on zero fuel.
        this.gateway_send(REMOTE_CENTRIFUGE_ID, hex"00");
        property_SB1_standby_credit_ledger();
    }

    // ─── AdapterFailover ─────────────────────────────────────────────────────

    /// @dev Arm, wait out the timelock, execute: the armed set installs as POOL_A's next session and the proposal
    ///      is consumed. Seeds: pool 0 is POOL_A, set 2 is [adapter0, adapter1], threshold 2.
    /// forge test --match-test test_failover_initiate_timelock_execute -vvv
    function test_failover_initiate_timelock_execute() public {
        this.failover_initiate(0, 2, 2);
        property_FO1_failover_ledger();

        vm.expectRevert(bytes(""));
        this.failover_execute_early_mustRevert(0);
        vm.expectRevert(bytes("FOUNDRY::ASSUME"));
        this.failover_execute(0);

        vm.warp(block.timestamp + FAILOVER_TIMELOCK);
        this.failover_execute(0);
        assertEq(multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, POOL_A), 2);
        assertEq(_activeList(POOL_A).length, 2);
        assertEq(multiAdapter.threshold(REMOTE_CENTRIFUGE_ID, POOL_A), 2);
        property_FO1_failover_ledger();

        vm.expectRevert(bytes(""));
        this.failover_execute_unarmed_mustRevert(REMOTE_CENTRIFUGE_ID, 1, 2);
    }

    /// @dev Both disarm paths make a later execute find nothing, even once the window opens.
    /// forge test --match-test test_failover_cancel_and_hub_veto -vvv
    function test_failover_cancel_and_hub_veto() public {
        this.failover_initiate(0, 6, 2);
        this.failover_stewardCancel(0);
        property_FO1_failover_ledger();

        this.failover_initiate(0, 6, 2);
        this.failover_hubVeto(0);
        property_FO1_failover_ledger();

        vm.warp(block.timestamp + FAILOVER_TIMELOCK);
        vm.expectRevert(bytes("FOUNDRY::ASSUME"));
        this.failover_execute(0);
        vm.expectRevert(IAdapterFailover.NoPendingFailover.selector);
        failover.executeFailover(REMOTE_CENTRIFUGE_ID, POOL_A, _failoverSet(6), 2);
        assertEq(multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, POOL_A), 1, "original set kept");
    }

    /// @dev A proposal is not tied to the session it was armed under: a hub reconfigure and a blocked session in
    ///      between do not disarm it, and it installs as the session after whatever is active at execution.
    /// forge test --match-test test_failover_survives_reconfigure -vvv
    function test_failover_survives_reconfigure() public {
        this.failover_initiate(0, 10, 2); // [adapter0, adapter1, standby]
        this.multiAdapter_reconfigurePool(1, 3, 2); // POOL_A session 2
        this.multiAdapter_blockSession(2, hex"0a"); // a POOL_A message: blocks POOL_A's active session 2
        assertEq(_activeList(POOL_A).length, 0, "active session blocked");

        vm.warp(block.timestamp + FAILOVER_TIMELOCK);
        this.failover_execute(0);
        assertEq(multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, POOL_A), 3);
        assertEq(address(_activeList(POOL_A)[2]), address(standby));

        this.multiAdapter_deliver(0, hex"0a");
        this.multiAdapter_deliver(2, hex"0a"); // the standby, via its underlying
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(hex"0a")), 1);
        _assertDeliveryBoundsHold();
    }

    /// @dev A failover can be POOL_B's first configuration, which moves its `SetPoolAdapters` off the global set.
    ///      The global per-session entry it had there must be cleared as `_install` clears it.
    /// forge test --match-test test_failover_first_configures_pool_b -vvv
    function test_failover_first_configures_pool_b() public {
        bytes memory payload = abi.encodePacked(countingProcessor.SET_POOL_B());
        this.multiAdapter_deliver(0, payload); // one global vote while POOL_B is unconfigured

        this.failover_updateSteward(1, true);
        this.failover_initiate(1, 6, 2); // POOL_B: [adapter0, adapter1, adapter2], 2-of-3
        vm.warp(block.timestamp + FAILOVER_TIMELOCK + 1);
        this.failover_execute(1);
        assertTrue(_route(payload) == POOL_B, "routes over POOL_B's own set once configured");

        this.multiAdapter_deliver(1, payload);
        this.multiAdapter_deliver(2, payload);
        assertEq(countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, keccak256(payload)), 1);
        _assertDeliveryBoundsHold();
        property_FO1_failover_ledger();
    }

    /// @dev Past a full second timelock the proposal lapses: it stays armed in storage but cannot execute.
    /// forge test --match-test test_failover_expires -vvv
    function test_failover_expires() public {
        this.failover_initiate(0, 2, 1);
        vm.warp(block.timestamp + 2 * uint256(FAILOVER_TIMELOCK) + 1);

        vm.expectRevert(bytes("FOUNDRY::ASSUME"));
        this.failover_execute(0);
        vm.expectRevert(bytes(""));
        this.failover_execute_expired_mustRevert(0);
        property_FO1_failover_ledger();
    }

    /// @dev Pools hold different steward values, then each is flipped: the other must not follow.
    /// forge test --match-test test_failover_steward_is_per_pool -vvv
    function test_failover_steward_is_per_pool() public {
        this.failover_updateSteward(1, true); // POOL_A true, POOL_B true
        this.failover_updateSteward(0, false); // POOL_A false, POOL_B stays true
        this.failover_updateSteward(1, false); // POOL_B false, POOL_A stays false
        this.failover_updateSteward(0, true); // POOL_A true, POOL_B stays false
        assertTrue(failover.steward(POOL_A, address(stewardActor)));
        assertFalse(failover.steward(POOL_B, address(stewardActor)));
    }

    /// forge test --match-test test_failover_negatives -vvv
    function test_failover_negatives() public {
        // POOL_B and the global pool have no steward; POOL_A's steward is nobody there.
        vm.expectRevert(bytes(""));
        this.failover_notSteward_mustRevert(2, false);
        vm.expectRevert(bytes(""));
        this.failover_notSteward_mustRevert(0, true);
        vm.expectRevert(bytes(""));
        this.failover_initiate_zeroThreshold_mustRevert(0, 3);
        vm.expectRevert(bytes(""));
        this.failover_fromHub_notEnvoy_mustRevert(1, true);
        vm.expectRevert(bytes(""));
        this.failover_fromHub_notEnvoy_mustRevert(1, false);

        this.failover_initiate(0, 6, 2);
        vm.warp(block.timestamp + FAILOVER_TIMELOCK);
        vm.expectRevert(bytes(""));
        this.failover_execute_wrongParams_mustRevert(0, 6, 3); // same set, other threshold
        vm.expectRevert(bytes(""));
        this.failover_execute_wrongParams_mustRevert(0, 2, 2); // other set, same threshold

        this.failover_updateManager(0, false);
        vm.expectRevert(bytes("FOUNDRY::ASSUME"));
        this.failover_execute(0);
        vm.expectRevert(bytes(""));
        this.failover_execute_noRole_mustRevert(0);

        // Revoking the steward on POOL_A leaves the armed proposal in place; only a disarm removes it.
        this.failover_updateSteward(0, false);
        this.failover_updateManager(0, true);
        this.failover_execute(0);
        property_FO1_failover_ledger();
    }

    function _assertDeliveryBoundsHold() internal {
        property_M1_threshold_respected();
        property_M4_vote_sum_bounded();
        property_G2_execution_conservation();
        property_G4_failed_messages_bounded();
        property_M1c_weighted_executions_bounded_by_deliveries();
        property_callCount_monotonic();
    }
}
