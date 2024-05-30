// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { OrderKey } from "../interfaces/Structs.sol";

/// @notice Gets the Permit2 context for an orderkey
library Permit2Lib {
    /**
     * @notice Converts OrderKey into a PermitTransferFrom
     */
    function toPermit(OrderKey memory order) internal pure returns (ISignatureTransfer.PermitTransferFrom memory) {
        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: order.inputToken, amount: order.inputAmount }),
            nonce: order.nonce,
            deadline: order.reactorContext.fillByDeadline
        });
    }

    /**
     * @notice Convert OrderKey into a permit object
     */
    function transferDetails(OrderKey memory order, address to)
        internal
        pure
        returns (ISignatureTransfer.SignatureTransferDetails memory)
    {
        return ISignatureTransfer.SignatureTransferDetails({ to: to, requestedAmount: order.inputAmount });
    }
}
