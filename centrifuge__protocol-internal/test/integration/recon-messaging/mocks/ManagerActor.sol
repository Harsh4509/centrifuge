// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IAdapter} from "../../../../src/core/messaging/interfaces/IAdapter.sol";
import {IGateway} from "../../../../src/core/messaging/interfaces/IGateway.sol";
import {IMultiAdapter} from "../../../../src/core/messaging/interfaces/IMultiAdapter.sol";

/// @dev Non-ward actor for the pool-manager path. The test contract is a ward, so its calls pass
///      `onlyAuthOrManager` regardless of manager state; this proxy's succeed iff it holds the role.
///      The role is granted separately on each contract, so the two `manager` mappings move independently.
contract ManagerActor {
    IMultiAdapter public immutable multiAdapter;
    IGateway public immutable gateway;

    constructor(IMultiAdapter multiAdapter_, IGateway gateway_) {
        multiAdapter = multiAdapter_;
        gateway = gateway_;
    }

    function handleAs(uint16 centrifugeId, bytes calldata payload, IAdapter adapter) external {
        multiAdapter.handle(centrifugeId, payload, adapter);
    }

    function voteAs(uint16 centrifugeId, bytes calldata payload, IAdapter adapter) external {
        multiAdapter.vote(centrifugeId, payload, adapter);
    }

    function executeAs(uint16 centrifugeId, bytes calldata payload, IAdapter adapter) external {
        multiAdapter.execute(centrifugeId, payload, adapter);
    }

    function gatewayHandle(uint16 centrifugeId, bytes calldata batch) external {
        gateway.handle(centrifugeId, batch);
    }

    function gatewayClearFailedMessage(uint16 centrifugeId, bytes calldata message) external {
        gateway.clearFailedMessage(centrifugeId, message);
    }
}
