// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {PoolId} from "../../../../src/core/types/PoolId.sol";
import {IMessageParser} from "../../../../src/core/messaging/interfaces/IMessageParser.sol";
import {IMessageHandler} from "../../../../src/core/messaging/interfaces/IMessageHandler.sol";

PoolId constant POOL_A = PoolId.wrap(1);
PoolId constant POOL_B = PoolId.wrap(2);

/// @dev Counts handle() invocations; can be forced to revert to exercise the Gateway's failedMessages path.
///      Also serves the framing view, as MessageProcessor does: framed and routed by the first byte, the way
///      MessageLib sizes a message by its type and routes it by the pool id it carries.
contract CountingProcessor is IMessageHandler, IMessageParser {
    /// @dev Source-restricted messages are `0xFE ++ bytes2(requiredSource) ++ ...`; encoded in the message
    ///      because the interface pins this `pure`. Anything else returns 0 = any source permitted.
    bytes1 public constant SOURCE_RESTRICTED_MAGIC = 0xFE;

    /// @dev Pool routing by first byte, which for bucketed payloads is the bucket: [POOL_A_FIRST, SET_POOL_B)
    ///      belongs to POOL_A, SET_POOL_B plays a `SetPoolAdapters` for POOL_B, everything else is global.
    uint8 public constant POOL_A_FIRST = 10;
    uint8 public constant SET_POOL_B = 15;

    /// @dev A message starting with a bucket byte (below this) is that one byte, so concatenated bucketed
    ///      payloads form a multi-message batch. Any other message is the whole remaining batch.
    uint8 public constant ONE_BYTE_BELOW = 16;

    mapping(uint16 centrifugeId => mapping(bytes32 msgHash => uint256)) public callCount;
    mapping(uint16 centrifugeId => mapping(bytes32 msgHash => bool)) public shouldFail;

    function handle(uint16 centrifugeId, bytes memory message) external {
        bytes32 msgHash = keccak256(message);
        require(!shouldFail[centrifugeId][msgHash], "CountingProcessor: forced failure");
        callCount[centrifugeId][msgHash]++;
    }

    /// @dev Intentionally unauthenticated: tests configure failure modes directly.
    function setFail(uint16 centrifugeId, bytes32 msgHash, bool fail) external {
        shouldFail[centrifugeId][msgHash] = fail;
    }

    function messageLength(bytes calldata message) external pure returns (uint16) {
        if (message.length > 0 && uint8(message[0]) < ONE_BYTE_BELOW) return 1;
        return uint16(message.length);
    }

    function messagePoolId(bytes calldata message) public pure returns (PoolId) {
        if (message.length == 0) return PoolId.wrap(0);
        uint8 first = uint8(message[0]);
        if (first == SET_POOL_B) return POOL_B;
        if (first >= POOL_A_FIRST && first < SET_POOL_B) return POOL_A;
        return PoolId.wrap(0); // GLOBAL_POOL
    }

    /// @dev Mirrors MessageLib: a `SetPoolAdapters` for a pool with no adapter set yet travels over the
    ///      global set, so the pool's first configuration can be delivered at all.
    function routePoolId(bytes calldata message, bool poolConfigured) external pure returns (PoolId) {
        if (!poolConfigured && message.length > 0 && uint8(message[0]) == SET_POOL_B) return PoolId.wrap(0);
        return messagePoolId(message);
    }

    function messageSourceCentrifugeId(bytes calldata message) external pure returns (uint16) {
        if (message.length >= 3 && message[0] == SOURCE_RESTRICTED_MAGIC) {
            return uint16(bytes2(message[1:3]));
        }
        return 0;
    }
}
