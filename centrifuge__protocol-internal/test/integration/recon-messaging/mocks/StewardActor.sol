// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {PoolId} from "../../../../src/core/types/PoolId.sol";
import {IAdapter} from "../../../../src/core/messaging/interfaces/IAdapter.sol";

import {AdapterFailover} from "../../../../src/managers/adapters/AdapterFailover.sol";

/// @dev The pool steward of `AdapterFailover`. A contract, not the test contract, because the test contract is
///      the envoy: keeping the two apart lets the negatives call `fromHub` as a non-envoy and the steward entry
///      points as a non-steward. Its role per pool is granted and revoked only through the envoy's `fromHub`.
contract StewardActor {
    AdapterFailover public immutable failover;

    constructor(AdapterFailover failover_) {
        failover = failover_;
    }

    function initiate(uint16 centrifugeId, PoolId poolId, IAdapter[] calldata adapters, uint8 threshold) external {
        failover.initiateFailover(centrifugeId, poolId, adapters, threshold);
    }

    function cancel(uint16 centrifugeId, PoolId poolId) external {
        failover.cancelFailover(centrifugeId, poolId);
    }

    function fromHub(PoolId poolId, bytes calldata payload) external {
        failover.fromHub(poolId, payload);
    }
}
