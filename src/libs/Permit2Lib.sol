// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { OrderKey } from "../interfaces/Structs.sol";
import { Input } from "../interfaces/ISettlementContract.sol";

/// @notice Gets the Permit2 context for an orderkey
library Permit2Lib {
    /**
     * @notice Converts OrderKey into a PermitTransferFrom
     */
    function toPermit(OrderKey memory order, address to)
        internal
        pure
        returns (
            ISignatureTransfer.SignatureTransferDetails[] memory batchSignatureTransfer,
            ISignatureTransfer.PermitBatchTransferFrom memory permitBatch
        )
    {
        uint256 numInputs = order.inputs.length;
        ISignatureTransfer.TokenPermissions[] memory permitted = new ISignatureTransfer.TokenPermissions[](numInputs);
        batchSignatureTransfer = new ISignatureTransfer.SignatureTransferDetails[](numInputs);

        for (uint256 i; i < numInputs; ++i) {
            address token = order.inputs[i].token;
            uint256 amount = order.inputs[i].amount;
            batchSignatureTransfer[i] = ISignatureTransfer.SignatureTransferDetails({ to: to, requestedAmount: amount });
            permitted[i] = ISignatureTransfer.TokenPermissions({ token: token, amount: amount });
        }

        // Probably should use a batch here.
        permitBatch = ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permitted,
            nonce: order.nonce,
            deadline: order.reactorContext.fillByDeadline
        });
    }

    /**
     * @notice Convert OrderKey into a permit object
     */
    // TODO: Is this needed?
    /* function transferDetails(Output[] memory outputs, address to)
        internal
        pure
        returns (ISignatureTransfer.SignatureTransferDetails[] memory batchSignatureTransfer)
    {
        uint256 numOuputs = outputs.length;
        batchSignatureTransfer = new ISignatureTransfer.SignatureTransferDetails[](numOuputs);
        for (uint256 i; i < numOutputs; ++i) {
            batchSignatureTransfer[i] = new ISignatureTransfer.SignatureTransferDetails({
                to: to,
                requestedAmount: outputs[i].amount
            });
        }
        return batchSignatureTransfer;
    } */
}
