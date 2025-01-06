// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ITheCompactClaims, BatchClaimWithWitness, BatchClaimComponent } from "the-compact//src/interfaces/ITheCompactClaims.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { Input, OnchainCrossChainOrder } from "../../interfaces/IERC7683.sol";
import { OrderContext, OrderKey } from "../../interfaces/Structs.sol";

import { CanCollectGovernanceFee } from "../../libs/CanCollectGovernanceFee.sol";
import { Permit2Lib } from "../../libs/Permit2Lib.sol";

/**
 * @notice Reactor Payment Handler.
 * Handles sending batches of tokens in and out of the reactor.
 */
abstract contract ReactorPayments is CanCollectGovernanceFee {
    using Permit2Lib for OrderKey;

    ITheCompactClaims public immutable COMPACT;

    constructor(address compact, address owner) payable CanCollectGovernanceFee(owner) {
        COMPACT = ITheCompactClaims(compact);
    }

    function _resolveLock(OnchainCrossChainOrder calldata order, bytes calldata allocatorSignature, bytes calldata sponsorSignature, address solvedBy) internal virtual {

        uint256 numInputs = order.inputs.length;
        BatchClaimComponent[] memory claims = new BatchClaimComponent[](numInputs);
        Input[] memory maxInputs = _getMaxInputs(order);
        for (uint256 i; i < numInputs; ++i) {
            claims[i] = BatchClaimComponent({
                id: uint256(0), // The token ID of the ERC6909 token to allocate. // TODO: get.
                allocatedAmount: maxInputs[i].amount, // The original allocated amount of ERC6909 tokens.
                amount: uint256(0) // The claimed token amount; specified by the arbiter. // TODO: get
            });
        }

        bool success = COMPACT.claim(BatchClaimWithWitness({
            allocatorSignature: allocatorSignature,
            sponsorSignature: sponsorSignature,
            sponsor: orderKey.swapper,
            nonce: orderKey.nonce,
            expires: orderKey.reactorContext.proofDeadline,
            witness: bytes32(0), // Hash of the witness data. // TODO:
            witnessTypestring: string(), // Witness typestring appended to existing typestring. // TODO:
            claims: claims,
            claimant: solvedBy
        }));
        require(success); // This should always be true.
    }
}
