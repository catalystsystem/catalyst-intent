// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { Input } from "../../interfaces/ISettlementContract.sol";
import { OrderContext, OrderKey } from "../../interfaces/Structs.sol";

import { CanCollectGovernanceFee } from "../../libs/CanCollectGovernanceFee.sol";
import { Permit2Lib } from "../../libs/Permit2Lib.sol";

/**
 * @notice Reactor Payment Handler.
 * Handles sending batches of tokens in and out of the reactor.
 */
abstract contract ReactorPayments is CanCollectGovernanceFee {
    using Permit2Lib for OrderKey;

    ISignatureTransfer public immutable PERMIT2;

    constructor(address permit2, address owner) payable CanCollectGovernanceFee(owner) {
        PERMIT2 = ISignatureTransfer(permit2);
    }

    /**
     * @notice Multi purpose order flow function that converts an order into a permit2
     * structure and provides relevant token flow protections:
     * - Orders the collection of tokens. This includes checking if the user has enough & approval.
     * - Verification of the signature for the order. This ensures the user has accepted the order conditions.
     * - Spend nonces. Disallow the same order from being claimed twice.
     */
    function _collectTokensViaPermit2(
        OrderKey memory orderKey,
        uint256[] memory permittedAmounts,
        uint32 permitDeadline,
        address owner,
        bytes32 witness,
        string memory witnessTypeString,
        bytes calldata signature
    ) internal virtual {
        (
            ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,
            ISignatureTransfer.SignatureTransferDetails[] memory transferDetails
        ) = orderKey.toPermit(permittedAmounts, address(this), permitDeadline);

        PERMIT2.permitWitnessTransferFrom(permitBatch, transferDetails, owner, witness, witnessTypeString, signature);
    }

    /**
     * @notice Collects tokens without permit2.
     * @dev Can only be used to collect tokens from msg.sender.
     * If inputs[i].amount * discount overflows the amount is set to inputs[i].amount.
     * This function does not verify whether the provided token addresses are actual token contracts
     * @param inputs Tokens to collect from msg.sender.
     * @param to Destination address for the collected tokens. To collect to this contract, set address(this).
     */
    function _collectTokensFromMsgSender(Input[] memory inputs, address to, uint16 discount) internal virtual {
        address from = msg.sender;
        uint256 numInputs = inputs.length;
        unchecked {
            for (uint256 i = 0; i < numInputs; ++i) {
                Input memory input = inputs[i];
                address token = input.token;
                uint256 amount = input.amount;
                // If discount == 0, then set amount to amount.
                // If the discount subtraction overflows, also set the amount to amount.
                // Otherwise, compute the discount as: amount - (amount * uint256(discount)) / uint256(type(uint16).max)
                amount = (discount != 0 && amount < type(uint256).max / uint256(discount))
                    ? amount - (amount * uint256(discount)) / uint256(type(uint16).max)
                    : amount;
                SafeTransferLib.safeTransferFrom(token, from, to, amount);
            }
        }
    }

    /**
     * @notice Sends a list of inputs to the target address.
     * @dev This function can be used for paying the filler or refunding the user in case of disputes.
     * @param inputs List of inputs that are to be paid.
     * @param to Destination address.
     */
    function _deliverTokens(Input[] memory inputs, address to, uint256 fee) internal virtual {
        // Read governance fee.
        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            Input memory input = inputs[i];
            address token = input.token;
            // Collect governance fee. Importantly, this also sets the value as collected.
            uint256 amount = input.amount;
            amount = fee == 0 ? amount : _collectGovernanceFee(token, amount, fee);
            // We don't need to check if token is deployed since we
            // got here. Reverting here would also freeze collateral.
            SafeTransferLib.safeTransfer(token, to, amount);
        }
    }
}
