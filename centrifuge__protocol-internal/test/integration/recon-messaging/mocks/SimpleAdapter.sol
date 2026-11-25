// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IAdapter} from "../../../../src/core/messaging/interfaces/IAdapter.sol";
import {IAdapterEntrypoint} from "../../../../src/core/messaging/interfaces/IAdapterEntrypoint.sol";

/// @dev Simulates a GMP adapter; the deliver* functions mimic inbound delivery from the remote chain. Its
///      entrypoint is the MultiAdapter, or, for the adapter a StandbyAdapter wraps, the standby: that one is
///      built before the standby exists, so the entrypoint can be set once afterwards.
contract SimpleAdapter is IAdapter {
    error EntrypointAlreadySet();

    IAdapterEntrypoint public entrypoint;
    uint16 public immutable remoteChainId;

    constructor(uint16 remoteChainId_, IAdapterEntrypoint entrypoint_) {
        remoteChainId = remoteChainId_;
        entrypoint = entrypoint_;
    }

    function setEntrypoint(IAdapterEntrypoint entrypoint_) external {
        require(address(entrypoint) == address(0), EntrypointAlreadySet());
        entrypoint = entrypoint_;
    }

    function deliver(bytes calldata payload) external {
        entrypoint.handle(remoteChainId, payload);
    }

    /// @dev Proof-adapter path: casts a vote without executing.
    function deliverVote(bytes calldata payload) external {
        entrypoint.vote(remoteChainId, payload);
    }

    /// @dev Deferred-execution path: consumes quorum votes if the threshold is met, else reverts NotEnoughVotes.
    function deliverExecute(bytes calldata payload) external {
        entrypoint.execute(remoteChainId, payload);
    }

    // ── IAdapter ──────────────────────────────────────────────────────────────

    // Outbound fan-out observability (S1/S2 in GatewayTargets)
    uint256 public sendCount;
    bytes32 public lastSentPayloadHash;
    uint256 public lastSentGasLimit;
    address public lastSentRefund;
    /// @dev A multi-pool batch dispatches once per pool through shared adapters, so the last hash alone
    ///      cannot tell which dispatches happened.
    mapping(bytes32 payloadHash => uint256) public sentCount;

    function send(uint16, bytes calldata payload, uint256 gasLimit, address refund) external payable returns (bytes32) {
        sendCount++;
        lastSentPayloadHash = keccak256(payload);
        lastSentGasLimit = gasLimit;
        lastSentRefund = refund;
        sentCount[keccak256(payload)]++;
        return bytes32(0);
    }

    /// @dev Outbound cost quote. ZERO by default, which is load-bearing: `Gateway._send` dispatches
    ///      whenever `fuel >= cost`, and the suite holds no ETH, so a zero quote is what lets every
    ///      ordinary send dispatch with `msg.value == 0`. A non-zero quote flips `_send` onto its
    ///      unpaid / NotEnoughGas branches, so it is raised ONLY inside the underpaid-batch handlers and
    ///      restored within the same transaction. `property_adapterEstimate_zero_between_txs` guards that.
    uint256 public estimatePerCall;

    function setEstimate(uint256 estimatePerCall_) external {
        estimatePerCall = estimatePerCall_;
    }

    function estimate(uint16, bytes calldata, uint256) external view returns (uint256) {
        return estimatePerCall;
    }
}
