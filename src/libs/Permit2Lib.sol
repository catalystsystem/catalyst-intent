// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { Input } from "../interfaces/ISettlementContract.sol";
import { OrderKey } from "../interfaces/Structs.sol";

/**
 * @notice Gets the Permit2 context for an orderkey
 */
library Permit2Lib {
    /**
     * @notice Converts an OrderKey into a PermitBatchTransferFrom
     */
    function toPermit(
        OrderKey memory order,
        uint256[] memory permittedAmounts,
        address to,
        uint32 deadline
    )
        internal
        pure
        returns (
            ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,
            ISignatureTransfer.SignatureTransferDetails[] memory transferDetails
        )
    {
        // Load the number of inputs. We need them to set the array size & convert each
        // input struct into a transferDetails struct.
        uint256 numInputs = order.inputs.length;
        ISignatureTransfer.TokenPermissions[] memory permitted = new ISignatureTransfer.TokenPermissions[](numInputs);
        transferDetails = new ISignatureTransfer.SignatureTransferDetails[](numInputs);

        // Iterate through each input.
        for (uint256 i; i < numInputs; ++i) {
            // Set the allowance. This is the explicit max allowed amount approved by the user.
            permitted[i] =
                ISignatureTransfer.TokenPermissions({ token: order.inputs[i].token, amount: permittedAmounts[i] });
            // Set our requested transfer. This has to be less than or equal to the allowance
            transferDetails[i] =
                ISignatureTransfer.SignatureTransferDetails({ to: to, requestedAmount: order.inputs[i].amount });
        }

        // Always use a batch transfer from. This allows us to easily standardize
        // token collections for multiple inputs.
        permitBatch =
            ISignatureTransfer.PermitBatchTransferFrom({ permitted: permitted, nonce: order.nonce, deadline: deadline });
    }

    function inputsToPermittedAmounts(Input[] memory inputs) internal pure returns (uint256[] memory permittedAmounts) {
        uint256 numInputs = inputs.length;
        permittedAmounts = new uint256[](numInputs);
        for (uint256 i = 0; i < numInputs; ++i) {
            permittedAmounts[i] = inputs[i].amount;
        }
    }
}
