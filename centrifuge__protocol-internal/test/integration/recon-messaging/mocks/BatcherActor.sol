// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IGateway} from "../../../../src/core/messaging/interfaces/IGateway.sol";

/// @dev Outbound-batching actor. `Gateway.withBatch` calls back into `msg.sender`, so the batch initiator
///      MUST be a contract: it has to call `lockCallback()` and issue its `send`s from inside that callback.
///      The test contract cannot play this role, because the callback would re-enter the fuzzer's own
///      handler frame. This actor is a ward of the gateway (it calls the `auth`-gated `send`).
///
///      `Mode` selects which part of the withBatch contract to exercise, including the failure paths that
///      are otherwise unreachable:
///      - `Normal`      lock, then N sends. The happy path plus `_endBatching`.
///      - `SkipLock`    omit `lockCallback()` -> `CallbackWasNotLocked`.
///      - `ForeignLock` the peer actor locks instead -> `CallbackWasNotFromSender`.
///      - `EmptyRevert` revert with empty returndata -> `CallFailedWithEmptyRevert`.
///      - `Nested`      lock, N sends, then re-enter `withBatch` -> the `isNested` branch.
contract BatcherActor {
    enum Mode {
        Normal,
        SkipLock,
        ForeignLock,
        EmptyRevert,
        Nested
    }

    IGateway public immutable gateway;

    /// @dev Only used as the non-batcher caller in `ForeignLock`; set once from Setup.
    BatcherActor public peer;

    constructor(IGateway gateway_) {
        gateway = gateway_;
    }

    function setPeer(BatcherActor peer_) external {
        peer = peer_;
    }

    // ── Batch initiation (called by the test contract) ─────────────────────────

    /// @dev Uses the 2-argument `withBatch` overload (no callback value).
    function startBatch(uint16 centrifugeId, bytes[] memory messages, Mode mode, address refund) external {
        gateway.withBatch(abi.encodeCall(this.runBatch, (centrifugeId, messages, mode)), refund);
    }

    /// @dev Uses the 3-argument overload with an explicit zero callback value. The suite holds no ETH, so
    ///      a non-zero callbackValue is not reachable; see the README coverage-gap note.
    function startBatchExplicitValue(uint16 centrifugeId, bytes[] memory messages, address refund) external {
        gateway.withBatch(abi.encodeCall(this.runBatch, (centrifugeId, messages, Mode.Normal)), 0, refund);
    }

    // ── Gateway callback ──────────────────────────────────────────────────────

    /// @dev Invoked BY the gateway via `msg.sender.call(data)`. A direct call reverts `CallbackIsLocked`,
    ///      since `_batcher` is zero outside a batch, so this needs no access control of its own.
    function runBatch(uint16 centrifugeId, bytes[] memory messages, Mode mode) external {
        if (mode == Mode.EmptyRevert) revert();

        if (mode == Mode.ForeignLock) {
            peer.lockFor();
        } else if (mode != Mode.SkipLock) {
            gateway.lockCallback();
        }

        for (uint256 i; i < messages.length; i++) {
            gateway.send(centrifugeId, messages[i], true, address(this));
        }

        if (mode == Mode.Nested) {
            bytes[] memory inner = new bytes[](1);
            inner[0] = messages[0];
            gateway.withBatch(abi.encodeCall(this.runBatch, (centrifugeId, inner, Mode.Normal)), address(this));
        }
    }

    /// @dev Lets the peer attempt the lock, so `msg.sender != _batcher` inside `lockCallback`.
    function lockFor() external {
        gateway.lockCallback();
    }
}
