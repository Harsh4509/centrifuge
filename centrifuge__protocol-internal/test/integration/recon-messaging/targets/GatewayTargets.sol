// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {MultiAdapterTargets} from "./MultiAdapterTargets.sol";

import {PoolId} from "../../../../src/core/types/PoolId.sol";
import {IAdapter} from "../../../../src/core/messaging/interfaces/IAdapter.sol";
import {MAX_ADAPTER_COUNT} from "../../../../src/core/messaging/interfaces/IMultiAdapter.sol";

import {BatcherActor} from "../mocks/BatcherActor.sol";
import {SimpleAdapter} from "../mocks/SimpleAdapter.sol";

abstract contract GatewayTargets is MultiAdapterTargets {
    /// @dev Send outbound; unpaidMode with zero-estimate adapters dispatches at once (fuel 0 >= cost 0).
    ///      centrifugeId is mostly clamped to the configured route; the rare escape keeps EmptyAdapterSet live.
    function gateway_send(uint16 centrifugeIdSeed, bytes calldata message) public validPayload(message) {
        uint16 cId = centrifugeIdSeed % 16 == 0 ? centrifugeIdSeed : REMOTE_CENTRIFUGE_ID;
        if (cId != REMOTE_CENTRIFUGE_ID) {
            gateway.send(cId, message, true, address(this)); // natural EmptyAdapterSet on dead routes
            return;
        }

        IAdapter[] memory list = _activeList(_route(message));
        bytes memory wrapped = _wrap(message);
        SendSnapshot memory before = _snapshotSends(list, wrapped);

        gateway.send(cId, message, true, address(this));

        _assertSends(list, wrapped, before, 1, "S1/S2: an active adapter was not sent the session-wrapped message once");
        _recordStandbySend(list, wrapped);
    }

    /// @dev Retry a failed message; with no failed entry it naturally reverts NotFailedMessage. A
    ///      successful retry executes without casting a vote, so only the execution delta is recorded.
    function gateway_retry(uint16 centrifugeIdSeed, bytes calldata message) public {
        uint16 cId = centrifugeIdSeed % 16 == 0 ? centrifugeIdSeed : REMOTE_CENTRIFUGE_ID;
        bytes memory m = _bucket(message);
        bytes32 msgHash = keccak256(m);
        uint256 failedBefore = gateway.failedMessages(cId, msgHash);

        gateway.retry(cId, m);

        // A retry re-runs an already-counted failed instance, no new votes: the quorum event was
        // credited at the failing session's threshold. Absorb the counter moves instead of re-crediting.
        _syncCumCounters(cId, msgHash);

        // When the consumed failure predates this session's baseline, its funding deliveries are not in
        // ghost_deliveries: bump the callCount baseline so the retried execution stays out of the delta.
        PoolId pool = _route(m);
        if (ghost_isTracked[cId][pool][msgHash] && failedBefore <= ghost_baselineFailedMessages[cId][pool][msgHash]) {
            ghost_baselineCallCount[cId][pool][msgHash]++;
        }
    }

    /// @dev Discard one failed-message instance; naturally reverts NotFailedMessage with nothing to clear.
    function gateway_clearFailedMessage(bytes calldata message) public {
        _clearFailedMessageAndCheck(message, false);
    }

    /// @dev Same as `gateway_clearFailedMessage`, submitted by the non-ward gateway pool manager.
    function gateway_managerClearFailedMessage(bytes calldata message) public {
        precondition(gateway.manager(countingProcessor.messagePoolId(_bucket(message)), address(managerActor)));
        _clearFailedMessageAndCheck(message, true);
    }

    function _clearFailedMessageAndCheck(bytes calldata message, bool viaManager) internal {
        bytes memory m = _bucket(message);
        bytes32 msgHash = keccak256(m);
        uint256 failedBefore = gateway.failedMessages(REMOTE_CENTRIFUGE_ID, msgHash);
        uint256 ccBefore = countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, msgHash);

        if (viaManager) managerActor.gatewayClearFailedMessage(REMOTE_CENTRIFUGE_ID, m);
        else gateway.clearFailedMessage(REMOTE_CENTRIFUGE_ID, m);

        eq(
            gateway.failedMessages(REMOTE_CENTRIFUGE_ID, msgHash),
            failedBefore - 1,
            "clearFailedMessage: failedMessages not decremented by exactly 1"
        );
        eq(
            countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, msgHash),
            ccBefore,
            "clearFailedMessage: message was executed"
        );

        // Discarding is not a quorum event; absorb the counter move so the next real failure is detected.
        _syncCumCounters(REMOTE_CENTRIFUGE_ID, msgHash);
    }

    function gateway_setPaused(bool paused) public {
        mockProtocolPauser.setPaused(paused);
    }

    /// @dev Gateway-side manager role toggle, mirroring `multiAdapter_updateManager`. The two roles are
    ///      separate mappings on separate contracts, so the fuzzer explores every combination of them.
    function gateway_updateManager(bool canManage) public {
        _gatewayUpdateManager(GLOBAL_POOL, canManage);
    }

    /// @dev The gateway checks the role against the pool the message NAMES, where MultiAdapter checks the
    ///      routed pool: for a fallback payload the two differ until its pool is configured.
    function gateway_updateManagerPool(uint8 poolSeed, bool canManage) public {
        _gatewayUpdateManager(_poolAt(poolSeed), canManage);
    }

    function _gatewayUpdateManager(PoolId pool, bool canManage) internal {
        gateway.updateManager(pool, address(managerActor), canManage);

        t(
            gateway.manager(pool, address(managerActor)) == canManage,
            "updateManager: gateway manager getter does not reflect the update"
        );
    }

    /// @dev MG1 – a gateway pool manager submits straight to `handle`, bypassing adapter quorum. That is a
    ///      trusted path, like the MultiAdapter manager, so no delivery bound applies to it; what must hold is
    ///      that each submitted message is processed exactly once: executed or recorded as failed, never both.
    ///      It casts no votes, so its instance is absorbed out of the delivery-bound ghosts the way
    ///      `gateway_retry` absorbs a vote-free execution: the per-session baselines move by what it
    ///      processed, so M1/G2/G4 keep measuring only quorum-driven executions.
    function gateway_managerHandle(bytes calldata payload) public validPayload(payload) {
        bytes memory p = _bucket(payload);
        precondition(gateway.manager(countingProcessor.messagePoolId(p), address(managerActor)));
        bytes32 msgHash = keccak256(p);
        PoolId pool = _route(p);
        uint256 ccBefore = countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, msgHash);
        uint256 failedBefore = gateway.failedMessages(REMOTE_CENTRIFUGE_ID, msgHash);

        // The gateway receives messages already stripped of the session prefix, so `p` goes in unwrapped.
        managerActor.gatewayHandle(REMOTE_CENTRIFUGE_ID, p);

        uint256 executed = countingProcessor.callCount(REMOTE_CENTRIFUGE_ID, msgHash) - ccBefore;
        uint256 failed = gateway.failedMessages(REMOTE_CENTRIFUGE_ID, msgHash) - failedBefore;
        eq(executed + failed, 1, "MG1: manager handle did not process the message exactly once");

        if (ghost_isTracked[REMOTE_CENTRIFUGE_ID][pool][msgHash]) {
            ghost_baselineCallCount[REMOTE_CENTRIFUGE_ID][pool][msgHash] += executed;
            ghost_baselineFailedMessages[REMOTE_CENTRIFUGE_ID][pool][msgHash] += failed;
        }
        _syncCumCounters(REMOTE_CENTRIFUGE_ID, msgHash);
    }

    /// @dev Make CountingProcessor reject a payload so the next handle() for it fails. Bucketed payload,
    ///      not a free bytes32 (a free hash never matches a delivery); keyed on the UNWRAPPED hash.
    function gateway_setProcessorFail(bytes memory payload, bool fail) public {
        countingProcessor.setFail(REMOTE_CENTRIFUGE_ID, keccak256(_bucket(payload)), fail);
    }

    // ─── Negative enforcement targets ────────────────────────────────────────
    // Each negative target ends with `require(false)`: successful runs count as reverted, so shrunk
    // traces stay short.

    /// @dev G7 – clearFailedMessage on a non-failed message must revert with NotFailedMessage.
    function gateway_clearFailedMessage_nonFailed_mustRevert(bytes calldata message) public {
        bytes32 msgHash = keccak256(message);
        precondition(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, msgHash) == 0);

        try gateway.clearFailedMessage(REMOTE_CENTRIFUGE_ID, message) {
            t(false, "G7: clearFailedMessage succeeded on non-failed message");
        } catch (bytes memory err) {
            t(checkError(err, "NotFailedMessage()"), "G7: wrong revert (expected NotFailedMessage)");
        }
        require(false);
    }

    /// @dev G8 – a batch claiming LOCAL origin is a forgery: anything reaching handle crossed a bridge.
    function gateway_handle_local_mustRevert(bytes calldata message) public validPayload(message) {
        // handle is `pauseable`; skip when paused so the wrong-revert check stays meaningful.
        precondition(!mockProtocolPauser.paused());

        try gateway.handle(LOCAL_CENTRIFUGE_ID, message) {
            t(false, "G8: handle accepted a locally-originated batch");
        } catch (bytes memory err) {
            t(checkError(err, "CannotBeReceivedLocally()"), "G8: wrong revert (expected CannotBeReceivedLocally)");
        }
        require(false);
    }

    /// @dev G9 – a message whose required source chain doesn't match the delivering chain must revert
    ///      SourceMismatch. The mock's `0xFE ++ bytes2(requiredSource)` prefix makes it restricted.
    function gateway_handle_sourceMismatch_mustRevert(uint16 wrongSource, bytes calldata payload)
        public
        validPayload(payload)
    {
        precondition(!mockProtocolPauser.paused());
        precondition(wrongSource != 0 && wrongSource != REMOTE_CENTRIFUGE_ID);

        bytes memory message = abi.encodePacked(countingProcessor.SOURCE_RESTRICTED_MAGIC(), wrongSource, payload);

        try gateway.handle(REMOTE_CENTRIFUGE_ID, message) {
            t(false, "G9: handle accepted a message from the wrong source chain");
        } catch (bytes memory err) {
            t(checkError(err, "SourceMismatch()"), "G9: wrong revert (expected SourceMismatch)");
        }
        require(false);
    }

    /// @dev G11 – an inbound batch whose messages name different pools must revert MalformedBatch: the batch
    ///      travels over the first message's pool's adapter set, so a later message for another pool would
    ///      otherwise ride on adapters that pool never trusted.
    function gateway_handle_mixedPoolBatch_mustRevert(bytes calldata first, bytes calldata second) public {
        precondition(!mockProtocolPauser.paused());
        bytes memory a = _bucket(first);
        bytes memory b = _bucket(second);
        precondition(!(countingProcessor.messagePoolId(a) == countingProcessor.messagePoolId(b)));

        try gateway.handle(REMOTE_CENTRIFUGE_ID, abi.encodePacked(a, b)) {
            t(false, "G11: handle accepted a batch mixing pools");
        } catch (bytes memory err) {
            t(checkError(err, "MalformedBatch()"), "G11: wrong revert (expected MalformedBatch)");
        }
        require(false);
    }

    /// @dev G3 – retry on a non-failed message must revert with NotFailedMessage.
    function gateway_retry_nonFailed_mustRevert(uint16 centrifugeId, bytes calldata message) public {
        bytes32 msgHash = keccak256(message);
        precondition(gateway.failedMessages(centrifugeId, msgHash) == 0); // negative-test setup
        // retry is `pauseable`; skip when paused so the wrong-revert check stays meaningful.
        precondition(!mockProtocolPauser.paused());

        try gateway.retry(centrifugeId, message) {
            t(false, "G3: retry succeeded on non-failed message");
        } catch (bytes memory err) {
            t(checkError(err, "NotFailedMessage()"), "G3: wrong revert (expected NotFailedMessage)");
        }
        require(false);
    }

    /// @dev G5 – inbound handle must revert Paused: vote once below threshold, pause, deliver the second.
    function gateway_handle_whenPaused_mustRevert(bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());
        bytes memory p = _bucket(payload);
        PoolId pool = _route(p);
        precondition(multiAdapter.threshold(REMOTE_CENTRIFUGE_ID, pool) == 2);
        precondition(_isActive(pool, address(adapter0)) && _isActive(pool, address(adapter1)));
        // adapter0's pre-delivery must be the FIRST positive vote: otherwise it hits threshold before
        // the pause and adapter1's delivery returns normally, tripping a false-positive `t(false)`.
        bytes memory wrapped = _wrap(p);
        int16[MAX_ADAPTER_COUNT] memory v = multiAdapter.votes(REMOTE_CENTRIFUGE_ID, _voteKey(pool, wrapped));
        for (uint8 i; i < MAX_ADAPTER_COUNT; i++) {
            precondition(v[i] == 0);
        }

        _captureBaselines(REMOTE_CENTRIFUGE_ID, p);
        adapter0.deliver(wrapped);
        _recordSuccessfulDelivery(REMOTE_CENTRIFUGE_ID, p);

        mockProtocolPauser.setPaused(true);

        try adapter1.deliver(wrapped) {
            t(false, "G5: deliver succeeded while paused");
        } catch (bytes memory err) {
            t(checkError(err, "Paused()"), "G5: wrong revert (expected Paused)");
        }

        // Rolled back by `require(false)` below; kept explicit.
        mockProtocolPauser.setPaused(false);
        require(false);
    }

    /// @dev G5b – retry must revert with Paused() when the protocol is paused.
    function gateway_retry_whenPaused_mustRevert(bytes calldata message) public {
        bytes memory m = _bucket(message);
        bytes32 msgHash = keccak256(m);
        precondition(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, msgHash) > 0); // need failed entry
        precondition(!mockProtocolPauser.paused());

        mockProtocolPauser.setPaused(true);

        try gateway.retry(REMOTE_CENTRIFUGE_ID, m) {
            t(false, "G5b: retry succeeded while paused");
        } catch (bytes memory err) {
            t(checkError(err, "Paused()"), "G5b: wrong revert (expected Paused)");
        }

        mockProtocolPauser.setPaused(false);
        require(false);
    }

    /// @dev G6 – blocking the active session empties the adapter set, so send must revert EmptyAdapterSet.
    function gateway_send_whenBlocked_mustRevert(bytes calldata message) public validPayload(message) {
        // send is `pauseable`; skip when paused so the wrong-revert check stays meaningful.
        precondition(!mockProtocolPauser.paused());

        PoolId pool = _route(message);
        uint16 sid = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, pool);
        precondition(!multiAdapter.blockedSession(REMOTE_CENTRIFUGE_ID, pool, sid));

        multiAdapter.blockSession(REMOTE_CENTRIFUGE_ID, pool, sid);

        try gateway.send(REMOTE_CENTRIFUGE_ID, message, true, address(this)) {
            t(false, "G6: send succeeded while active session blocked");
        } catch (bytes memory err) {
            t(checkError(err, "EmptyAdapterSet()"), "G6: wrong revert (expected EmptyAdapterSet)");
        }

        multiAdapter.unblockSession(REMOTE_CENTRIFUGE_ID, pool, sid);
        require(false);
    }

    /// @dev G10 – `file` with an unknown param must revert rather than silently no-op. Only the negative
    ///      is fuzzed: a positive `file` handler would let the fuzzer repoint `processor`/`adapter` at an
    ///      arbitrary address and invalidate the whole suite. The recognized branches are covered by Setup.
    function gateway_file_unrecognizedParam_mustRevert(bytes32 what) public {
        precondition(what != "messageGas" && what != "processor" && what != "adapter");

        try gateway.file(what, address(mockMessageGas)) {
            t(false, "G10: file accepted an unrecognized param");
        } catch (bytes memory err) {
            t(checkError(err, "FileUnrecognizedParam()"), "G10: wrong revert (expected FileUnrecognizedParam)");
        }
        require(false);
    }

    /// @dev MG2 – without the gateway manager role of the pool the message names, a non-ward cannot submit
    ///      to `handle`, whatever its other roles: neither the MultiAdapter role nor another pool's gateway
    ///      role may open the gateway's quorum bypass.
    function gateway_managerHandle_notManager_mustRevert(bytes calldata payload) public validPayload(payload) {
        precondition(!gateway.manager(countingProcessor.messagePoolId(_bucket(payload)), address(managerActor)));
        // `pauseable` runs before the manager check.
        precondition(!mockProtocolPauser.paused());

        try managerActor.gatewayHandle(REMOTE_CENTRIFUGE_ID, _bucket(payload)) {
            t(false, "MG2: non-manager submitted to gateway.handle");
        } catch (bytes memory err) {
            t(checkError(err, "NotAuthorized()"), "MG2: wrong revert (expected NotAuthorized)");
        }
        require(false);
    }

    /// @dev MG3 – without the gateway manager role a non-ward cannot discard a failed message. The role
    ///      check precedes the failed-message lookup, so this holds whether or not one is outstanding.
    function gateway_managerClearFailedMessage_notManager_mustRevert(bytes calldata message) public {
        precondition(!gateway.manager(countingProcessor.messagePoolId(_bucket(message)), address(managerActor)));

        try managerActor.gatewayClearFailedMessage(REMOTE_CENTRIFUGE_ID, _bucket(message)) {
            t(false, "MG3: non-manager cleared a failed message");
        } catch (bytes memory err) {
            t(checkError(err, "NotAuthorized()"), "MG3: wrong revert (expected NotAuthorized)");
        }
        require(false);
    }

    // ─── Outbound batching targets ───────────────────────────────────────────
    // `withBatch` calls back into `msg.sender`, so every batch is initiated through `batcher`
    // (see mocks/BatcherActor.sol). Positive targets mutate state and carry inline asserts, so
    // they must NOT end with `require(false)`.

    /// @dev The batching contract: messages sent inside one batch coalesce per pool. Each pool the messages
    ///      name gets exactly ONE dispatch, carrying the concatenation of that pool's messages and sent
    ///      through the pool's routed adapter set. Adapters are shared between pools, so an adapter in
    ///      several routed sets is dispatched to once per pool.
    function gateway_withBatch(uint8 countSeed, bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused()); // send is `pauseable`
        bytes[] memory messages = _batchMessages(countSeed, payload);
        (Dispatch[] memory planned, uint256[3] memory sendsBefore) = _planDispatches(messages);

        batcher.startBatch(REMOTE_CENTRIFUGE_ID, messages, BatcherActor.Mode.Normal, address(batcher));

        _assertDispatched(planned, sendsBefore);
    }

    /// @dev Same contract via the 3-argument overload with an explicit zero callbackValue.
    function gateway_withBatch_explicitValue(uint8 countSeed, bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());
        bytes[] memory messages = _batchMessages(countSeed, payload);
        (Dispatch[] memory planned, uint256[3] memory sendsBefore) = _planDispatches(messages);

        batcher.startBatchExplicitValue(REMOTE_CENTRIFUGE_ID, messages, address(batcher));

        _assertDispatched(planned, sendsBefore);
    }

    /// @dev Same contract with messages longer than a transient chunk: the batch slot then spans several
    ///      32-byte transient slots, and every append after the first writes across a chunk boundary. BT3
    ///      checks the dispatched bytes, so a chunk-index slip in that storage shows as a corrupted batch.
    function gateway_withBatch_longMessages(uint8 countSeed, bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());
        precondition(payload.length > 32);
        bytes[] memory messages = _batchMessages(countSeed, payload);
        for (uint256 i; i < messages.length; i++) {
            messages[i] = abi.encodePacked(messages[i], payload); // keeps the leading bucket byte, so the pool is unchanged
        }
        (Dispatch[] memory planned, uint256[3] memory sendsBefore) = _planDispatches(messages);

        batcher.startBatch(REMOTE_CENTRIFUGE_ID, messages, BatcherActor.Mode.Normal, address(batcher));

        _assertDispatched(planned, sendsBefore);
    }

    /// @dev Nested batching: the inner `withBatch` must NOT dispatch (only the outermost one settles), so
    ///      re-entering it appends one more message to its pool's slot and each pool is still ONE dispatch.
    ///      A second dispatch here would mean the nesting guard leaked.
    function gateway_withBatch_nested(uint8 countSeed, bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());
        bytes[] memory messages = _batchMessages(countSeed, payload);

        // The nested callback re-sends messages[0], appended after the outer batch.
        bytes[] memory sent = new bytes[](messages.length + 1);
        for (uint256 i; i < messages.length; i++) {
            sent[i] = messages[i];
        }
        sent[messages.length] = messages[0];
        (Dispatch[] memory planned, uint256[3] memory sendsBefore) = _planDispatches(sent);

        batcher.startBatch(REMOTE_CENTRIFUGE_ID, messages, BatcherActor.Mode.Nested, address(batcher));

        _assertDispatched(planned, sendsBefore);
    }

    // ─── Batching negative targets ───────────────────────────────────────────

    /// @dev BT4 – the callback must call lockCallback(), else withBatch reverts CallbackWasNotLocked.
    function gateway_withBatch_noLock_mustRevert(bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());
        bytes[] memory messages = _singleton(_bucket(payload));
        precondition(_activeList(_route(messages[0])).length > 0);

        try batcher.startBatch(REMOTE_CENTRIFUGE_ID, messages, BatcherActor.Mode.SkipLock, address(batcher)) {
            t(false, "BT4: withBatch succeeded without lockCallback");
        } catch (bytes memory err) {
            t(checkError(err, "CallbackWasNotLocked()"), "BT4: wrong revert (expected CallbackWasNotLocked)");
        }
        require(false);
    }

    /// @dev BT5 – only the batcher itself may lock: a different contract locking must revert
    ///      CallbackWasNotFromSender. Also exercises the non-empty revert bubble-up in withBatch.
    function gateway_withBatch_foreignLock_mustRevert(bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());
        bytes[] memory messages = _singleton(_bucket(payload));
        precondition(_activeList(_route(messages[0])).length > 0);

        try batcher.startBatch(REMOTE_CENTRIFUGE_ID, messages, BatcherActor.Mode.ForeignLock, address(batcher)) {
            t(false, "BT5: a non-batcher contract locked the callback");
        } catch (bytes memory err) {
            t(checkError(err, "CallbackWasNotFromSender()"), "BT5: wrong revert (expected CallbackWasNotFromSender)");
        }
        require(false);
    }

    /// @dev BT6 – a callback reverting with EMPTY returndata must surface as CallFailedWithEmptyRevert
    ///      rather than a silent success or an empty bubble-up.
    function gateway_withBatch_emptyRevert_mustRevert(bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());
        bytes[] memory messages = _singleton(_bucket(payload));
        precondition(_activeList(_route(messages[0])).length > 0);

        try batcher.startBatch(REMOTE_CENTRIFUGE_ID, messages, BatcherActor.Mode.EmptyRevert, address(batcher)) {
            t(false, "BT6: withBatch succeeded on an empty-reverting callback");
        } catch (bytes memory err) {
            t(checkError(err, "CallFailedWithEmptyRevert()"), "BT6: wrong revert (expected CallFailedWithEmptyRevert)");
        }
        require(false);
    }

    /// @dev BT7 – lockCallback outside any batch must revert CallbackIsLocked (`_batcher` is zero).
    function gateway_lockCallback_outsideBatch_mustRevert() public {
        precondition(!gateway.isBatching());

        try gateway.lockCallback() {
            t(false, "BT7: lockCallback succeeded outside a batch");
        } catch (bytes memory err) {
            t(checkError(err, "CallbackIsLocked()"), "BT7: wrong revert (expected CallbackIsLocked)");
        }
        require(false);
    }

    // ─── Underpaid-batch / repay targets ─────────────────────────────────────
    // `_send` dispatches whenever `fuel >= cost`, and the suite holds no ETH, so fuel is always 0.
    // The unpaid and NotEnoughGas branches therefore exist only while an adapter quotes a non-zero
    // cost. The quote is raised and restored INSIDE one handler: Echidna runs each handler as its own
    // transaction, so no other handler can observe a raised quote, and a revert rolls the raise back
    // with everything else. Restore BEFORE any catch, since a catch does not undo the outer frame.
    // `property_adapterEstimate_zero_between_txs` is the standing guard.

    /// @dev RETENTION half. Quotes non-zero, sends, restores the quote, and deliberately leaves the batch
    ///      outstanding across the transaction boundary. This is what makes the underpaid state space real:
    ///      the fuzzer can now interleave a pause, a `blockSession` or a reconfigure between retention and
    ///      settlement, none of which the atomic shortcut below can ever produce.
    function gateway_send_underpaid(bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());
        bytes memory m = _bucket(payload);
        IAdapter[] memory list = _activeList(_route(m));
        precondition(_hasPricedAdapter(list));

        bytes32 batchHash = keccak256(m);
        (, uint64 counterBefore) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);

        bytes memory wrapped = _wrap(m);
        SendSnapshot memory before = _snapshotSends(list, wrapped);

        _setAllEstimates(1);
        gateway.send(REMOTE_CENTRIFUGE_ID, m, true, address(this));
        _setAllEstimates(0); // restore before any assertion can revert

        (, uint64 counterAfter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        eq(uint256(counterAfter), uint256(counterBefore) + 1, "U1: underpaid batch was not retained");
        _assertSends(list, wrapped, before, 0, "U7: a retained batch must not reach the adapter");

        _recordUnderpaidRetained(REMOTE_CENTRIFUGE_ID, batchHash);
    }

    /// @dev SETTLEMENT half. Cost is re-quoted at repay time, so with the quote back at 0 the retained
    ///      batch settles on zero fuel. A revert here is the interesting failure, and a plain revert would be
    ///      dropped like any handler revert, so it is caught and reported once its preconditions hold.
    function gateway_repay(bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());

        bytes memory m = _bucket(payload);
        bytes32 batchHash = keccak256(m);
        (, uint64 counterBefore) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        precondition(counterBefore > 0);

        IAdapter[] memory list = _activeList(_route(m));
        if (list.length == 0) {
            // The route's active session was blocked since retention, so no adapter can send: the batch stays retained
            try gateway.repay(REMOTE_CENTRIFUGE_ID, m, address(this)) {
                t(false, "U2: a batch was repaid with no adapter to send it");
            } catch {}
            (, uint64 counterKept) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
            eq(uint256(counterKept), uint256(counterBefore), "U2: a refused repay consumed an instance");
            return;
        }
        bytes memory wrapped = _wrap(m);
        SendSnapshot memory before = _snapshotSends(list, wrapped);

        try gateway.repay(REMOTE_CENTRIFUGE_ID, m, address(this)) {}
        catch {
            t(false, "U2: a retained batch could not be repaid");
        }

        (, uint64 counterAfter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        eq(uint256(counterAfter), uint256(counterBefore) - 1, "U2: repay did not consume exactly one instance");
        _assertSends(list, wrapped, before, 1, "U3: repay did not dispatch the retained batch");

        _recordUnderpaidSettled(REMOTE_CENTRIFUGE_ID, batchHash);
        _recordStandbySend(list, wrapped);
    }

    /// @dev Shortcut (needs a prerequisite send, so not a clamp): the full cycle in one transaction. Kept
    ///      alongside the split pair above so the `repay` lines stay covered even if the fuzzer rarely
    ///      pairs the two halves. It touches no ledger ghost BY DESIGN: retention and settlement cancel
    ///      within the transaction, and a revert anywhere rolls both back, so U6 stays consistent.
    function shortcut_gateway_repay_underpaid(bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused()); // send and repay are both `pauseable`
        bytes memory m = _bucket(payload);
        IAdapter[] memory list = _activeList(_route(m));
        precondition(_hasPricedAdapter(list));

        bytes32 batchHash = keccak256(m);
        (, uint64 counterBefore) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);

        // Step 1: quote non-zero so `fuel(0) >= cost` fails and the batch is retained, not dispatched.
        _setAllEstimates(1);
        gateway.send(REMOTE_CENTRIFUGE_ID, m, true, address(this));

        (, uint64 afterSend) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        eq(uint256(afterSend), uint256(counterBefore) + 1, "U1: underpaid batch was not retained");

        // Step 2: drop the quote, then settle. Restores the fixture before any assertion can revert.
        _setAllEstimates(0);

        bytes memory wrapped = _wrap(m);
        SendSnapshot memory before = _snapshotSends(list, wrapped);

        gateway.repay(REMOTE_CENTRIFUGE_ID, m, address(this));

        (, uint64 afterRepay) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        eq(uint256(afterRepay), uint256(afterSend) - 1, "U2: repay did not consume exactly one instance");
        _assertSends(list, wrapped, before, 1, "U3: repay did not dispatch the retained batch");
        // A real dispatch, so the standby credit it gave is the harness's to account for.
        _recordStandbySend(list, wrapped);
    }

    /// @dev U4 – an unfunded send outside unpaid mode must revert NotEnoughGas rather than silently
    ///      retaining or dropping the message.
    function gateway_send_notEnoughGas_mustRevert(bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());
        precondition(_hasPricedAdapter(_activeList(_route(payload))));

        _setAllEstimates(1);

        try gateway.send(REMOTE_CENTRIFUGE_ID, payload, false, address(this)) {
            _setAllEstimates(0);
            t(false, "U4: unfunded send succeeded outside unpaid mode");
        } catch (bytes memory err) {
            _setAllEstimates(0);
            t(checkError(err, "NotEnoughGas()"), "U4: wrong revert (expected NotEnoughGas)");
        }
        require(false);
    }

    /// @dev U5 – repay on a batch that was never underpaid must revert NotUnderpaidBatch.
    function gateway_repay_nonUnderpaid_mustRevert(bytes calldata payload) public validPayload(payload) {
        precondition(!mockProtocolPauser.paused());

        bytes memory m = _bucket(payload);
        (, uint64 counter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, keccak256(m));
        precondition(counter == 0);

        try gateway.repay(REMOTE_CENTRIFUGE_ID, m, address(this)) {
            t(false, "U5: repay succeeded on a non-underpaid batch");
        } catch (bytes memory err) {
            t(checkError(err, "NotUnderpaidBatch()"), "U5: wrong revert (expected NotUnderpaidBatch)");
        }
        require(false);
    }

    /// @dev Whether `_setAllEstimates(1)` makes a send through `list` cost anything. The standby's `estimate` is
    ///      pure 0 by design, so a standby-only set always dispatches on zero fuel and the unpaid branches the
    ///      underpaid handlers assert cannot exist for it. An empty set fails this too (EmptyAdapterSet).
    function _hasPricedAdapter(IAdapter[] memory list) internal view returns (bool) {
        for (uint256 i; i < list.length; i++) {
            if (address(list[i]) != address(standby)) return true;
        }
        return false;
    }

    /// @dev Quote on every adapter, not just the active ones: `MultiAdapter.estimate` sums over the
    ///      ACTIVE set, and a reconfigure can install any subset.
    function _setAllEstimates(uint256 value) internal {
        adapter0.setEstimate(value);
        adapter1.setEstimate(value);
        adapter2.setEstimate(value);
    }

    // ─── Send-count helpers ──────────────────────────────────────────────────

    /// @dev Per adapter: how often it was sent these exact bytes, and its total sends. The standby has no send
    ///      total; its per-payload count is its credit (see `_sentCount`).
    struct SendSnapshot {
        uint256[] perPayload;
        uint256[] total;
    }

    function _snapshotSends(IAdapter[] memory list, bytes memory wrapped)
        internal
        view
        returns (SendSnapshot memory snap)
    {
        snap.perPayload = new uint256[](list.length);
        snap.total = new uint256[](list.length);
        for (uint256 i; i < list.length; i++) {
            snap.perPayload[i] = _sentCount(list[i], wrapped);
            if (address(list[i]) != address(standby)) snap.total[i] = SimpleAdapter(address(list[i])).sendCount();
        }
    }

    /// @dev Each adapter in `list` was sent `wrapped` exactly `delta` times and nothing else.
    function _assertSends(
        IAdapter[] memory list,
        bytes memory wrapped,
        SendSnapshot memory before,
        uint256 delta,
        string memory reason
    ) internal {
        for (uint256 i; i < list.length; i++) {
            eq(_sentCount(list[i], wrapped), before.perPayload[i] + delta, reason);
            if (address(list[i]) == address(standby)) continue;
            eq(SimpleAdapter(address(list[i])).sendCount(), before.total[i] + delta, reason);
        }
    }

    // ─── Batching helpers ────────────────────────────────────────────────────

    /// @dev 1..3 bucketed messages. Buckets span the pools, so one batch can name several pools.
    function _batchMessages(uint8 countSeed, bytes memory payload) internal returns (bytes[] memory messages) {
        uint256 n = between(uint256(countSeed), 1, 3);
        messages = new bytes[](n);
        for (uint256 i; i < n; i++) {
            messages[i] = _bucket(abi.encodePacked(payload, uint8(i)));
        }
    }

    function _singleton(bytes memory message) internal pure returns (bytes[] memory messages) {
        messages = new bytes[](1);
        messages[0] = message;
    }

    struct Dispatch {
        IAdapter[] list;
        bytes wrapped;
        uint256[] sentBefore; // per set member: identical bytes may have been dispatched by an earlier batch
    }

    /// @dev The dispatches a batch of `sent` must produce, computed before it runs: messages grouped by the pool
    ///      they name (the gateway's batch slot), concatenated in send order, each group wrapped with and sent
    ///      through its routed pool's set. Also snapshots the simple adapters' send totals.
    function _planDispatches(bytes[] memory sent)
        internal
        returns (Dispatch[] memory planned, uint256[3] memory sendsBefore)
    {
        PoolId[] memory pools = new PoolId[](sent.length);
        bytes[] memory batches = new bytes[](sent.length);
        uint256 groups;
        for (uint256 i; i < sent.length; i++) {
            PoolId pool = countingProcessor.messagePoolId(sent[i]);
            uint256 g;
            while (g < groups && !(pools[g] == pool)) g++;
            if (g == groups) pools[groups++] = pool;
            batches[g] = abi.encodePacked(batches[g], sent[i]);
        }

        planned = new Dispatch[](groups);
        for (uint256 g; g < groups; g++) {
            planned[g].list = _activeList(_route(batches[g]));
            precondition(planned[g].list.length > 0); // else EmptyAdapterSet on dispatch
            planned[g].wrapped = _wrap(batches[g]);
            planned[g].sentBefore = new uint256[](planned[g].list.length);
            for (uint256 i; i < planned[g].list.length; i++) {
                planned[g].sentBefore[i] = _sentCount(planned[g].list[i], planned[g].wrapped);
            }
        }

        sendsBefore = [adapter0.sendCount(), adapter1.sendCount(), adapter2.sendCount()];
    }

    /// @dev Each planned dispatch reached each member of its set exactly once (BT3, per payload, standby
    ///      included), and no simple adapter was sent anything else (BT2). A dispatch's bytes are unique to it,
    ///      so per-payload counters tell the dispatches apart.
    function _assertDispatched(Dispatch[] memory planned, uint256[3] memory sendsBefore) internal {
        t(!gateway.isBatching(), "BT1: isBatching still true after withBatch returned");

        for (uint256 g; g < planned.length; g++) {
            for (uint256 i; i < planned[g].list.length; i++) {
                eq(
                    _sentCount(planned[g].list[i], planned[g].wrapped),
                    planned[g].sentBefore[i] + 1,
                    "BT3: a pool's dispatch is not the wrapped concatenation of its messages"
                );
            }
            _recordStandbySend(planned[g].list, planned[g].wrapped);
        }

        SimpleAdapter[3] memory adapters = [adapter0, adapter1, adapter2];
        for (uint256 a; a < 3; a++) {
            uint256 expectedSends;
            for (uint256 g; g < planned.length; g++) {
                if (_contains(planned[g].list, address(adapters[a]))) expectedSends++;
            }
            eq(
                adapters[a].sendCount(),
                sendsBefore[a] + expectedSends,
                "BT2: batch did not coalesce into exactly one dispatch per pool"
            );
        }
    }
}
