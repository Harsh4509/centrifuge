// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {GatewayTargets} from "./GatewayTargets.sol";

/// @dev The StandbyAdapter's own surface. Its credits come from dispatches the gateway targets make while it is in
///      a set (see `multiAdapter_reconfigureWithStandby`); its inbound votes go through `_inbound`, so every
///      delivery target already votes through it.
abstract contract StandbyTargets is GatewayTargets {
    /// @dev SB2 – anyone can forward a credited payload: exactly one credit is consumed, and the underlying is
    ///      sent the same bytes once, with the gas originally requested plus the standby frame's reserve and
    ///      the 64/63 that frame's boundary costs, refunding the caller.
    function standby_forward(uint8 creditSeed) public {
        bytes memory wrapped = _creditedPayload(creditSeed);
        bytes32 id = _standbyId(wrapped);
        uint256 creditBefore = standby.forwardable(id);
        precondition(creditBefore > 0);
        uint256 sendsBefore = underlying.sendCount();

        standby.forward(REMOTE_CENTRIFUGE_ID, wrapped, DISPATCH_GAS_LIMIT);
        ghost_standbyForwarded[id]++;

        eq(standby.forwardable(id), creditBefore - 1, "SB2: forward did not consume exactly one credit");
        eq(underlying.sendCount(), sendsBefore + 1, "SB2: forward did not dispatch through the underlying once");
        t(underlying.lastSentPayloadHash() == keccak256(wrapped), "SB2: forward altered the payload");
        eq(
            underlying.lastSentGasLimit(),
            (DISPATCH_GAS_LIMIT + mockMessageGas.RECEIVE_COST()) * 64 / 63,
            "SB2: forward gas limit is not the requested one plus the standby frame"
        );
        t(underlying.lastSentRefund() == address(this), "SB2: forward did not refund the caller");
        // An adapter wrapped by the standby that prices its own receive path reads the gas service through it.
        t(
            address(standby.messageGas()) == address(multiAdapter.messageGas()),
            "SB2: the standby does not expose its entrypoint's gas service"
        );
    }

    /// @dev SB3 – a payload the standby was never sent cannot be forwarded: forwards never exceed sends, which
    ///      is what keeps the standby's vote as trustworthy as the others'.
    function standby_forward_uncredited_mustRevert(bytes calldata payload) public {
        precondition(standby.forwardable(_standbyId(payload)) == 0);

        try standby.forward(REMOTE_CENTRIFUGE_ID, payload, DISPATCH_GAS_LIMIT) {
            t(false, "SB3: forwarded a payload the standby was never sent");
        } catch (bytes memory err) {
            t(checkError(err, "NotForwardable()"), "SB3: wrong revert (expected NotForwardable)");
        }
        require(false);
    }

    /// @dev SB3b – a credit is bound to the gas limit it was sent with: forwarding the same payload with any
    ///      other gas limit finds no credit.
    function standby_forward_wrongGas_mustRevert(uint8 creditSeed, uint256 gasLimit) public {
        bytes memory wrapped = _creditedPayload(creditSeed);
        precondition(gasLimit != DISPATCH_GAS_LIMIT);

        try standby.forward(REMOTE_CENTRIFUGE_ID, wrapped, gasLimit) {
            t(false, "SB3b: forwarded a credit under a different gas limit");
        } catch (bytes memory err) {
            t(checkError(err, "NotForwardable()"), "SB3b: wrong revert (expected NotForwardable)");
        }
        require(false);
    }

    /// @dev SB4 – a forward must pay what the underlying quotes. The quote is raised and restored within this
    ///      handler, before the catch (see the underpaid-batch targets for why).
    function standby_forward_underpaid_mustRevert(uint8 creditSeed) public {
        bytes memory wrapped = _creditedPayload(creditSeed);
        precondition(standby.forwardable(_standbyId(wrapped)) > 0);

        underlying.setEstimate(1);
        try standby.forward(REMOTE_CENTRIFUGE_ID, wrapped, DISPATCH_GAS_LIMIT) {
            underlying.setEstimate(0);
            t(false, "SB4: forward succeeded below the underlying's quote");
        } catch (bytes memory err) {
            underlying.setEstimate(0);
            t(checkError(err, "NotEnoughValue()"), "SB4: wrong revert (expected NotEnoughValue)");
        }
        require(false);
    }

    /// @dev SB5 – only the MultiAdapter may credit the standby: a direct send would mint a forwardable vote.
    function standby_send_notEntrypoint_mustRevert(bytes calldata payload) public {
        try standby.send(REMOTE_CENTRIFUGE_ID, payload, DISPATCH_GAS_LIMIT, address(this)) {
            t(false, "SB5: a non-entrypoint credited the standby");
        } catch (bytes memory err) {
            t(checkError(err, "NotEntrypoint()"), "SB5: wrong revert (expected NotEntrypoint)");
        }
        require(false);
    }

    /// @dev SB6 – only the underlying may vote through the standby; anyone else would cast the standby's vote.
    function standby_inbound_notUnderlying_mustRevert(uint8 kind, bytes calldata payload) public {
        uint8 k = kind % 3;
        bytes memory wrapped = _wrap(_bucket(payload));

        if (k == 0) {
            try standby.handle(REMOTE_CENTRIFUGE_ID, wrapped) {
                t(false, "SB6: a non-underlying delivered through the standby");
            } catch (bytes memory err) {
                t(checkError(err, "NotUnderlying()"), "SB6: wrong revert on handle (expected NotUnderlying)");
            }
        } else if (k == 1) {
            try standby.vote(REMOTE_CENTRIFUGE_ID, wrapped) {
                t(false, "SB6: a non-underlying voted through the standby");
            } catch (bytes memory err) {
                t(checkError(err, "NotUnderlying()"), "SB6: wrong revert on vote (expected NotUnderlying)");
            }
        } else {
            try standby.execute(REMOTE_CENTRIFUGE_ID, wrapped) {
                t(false, "SB6: a non-underlying executed through the standby");
            } catch (bytes memory err) {
                t(checkError(err, "NotUnderlying()"), "SB6: wrong revert on execute (expected NotUnderlying)");
            }
        }
        require(false);
    }

    function _creditedPayload(uint8 creditSeed) internal returns (bytes memory) {
        uint256 n = ghost_standbyPayloads.length;
        precondition(n > 0);
        return ghost_standbyPayloads[between(uint256(creditSeed), 0, n - 1)];
    }
}
