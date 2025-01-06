// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { BaseReactor } from "./BaseReactor.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    IOriginSettler,
    ResolvedCrossChainOrder,
    Open
} from "../interfaces/IERC7683.sol";


import { CatalystOrderData, InputDescription } from "../libs/CatalystOrderType.sol";

import {
    ITheCompactClaims,
    BatchClaimWithWitness
} from "the-compact/src/interfaces/ITheCompactClaims.sol";


import {
    BatchClaimComponent
} from "the-compact/src/types/Components.sol";

/**
 * @title Base Cross-chain intent Reactor
 * @notice Cross-chain intent resolver. Implements core logic that is shared between all
 * reactors like token collection, order interfaces, order resolution:
 * - Optimistic Payout: Orders are assumed to have been filled correctly by the solver if not disputed.
 * - Order Dispute: Orders can be disputed such that proof of fulfillment has to be made.
 * - Oracle Interaction: To provide the relevant proofs against order disputes.
 *
 * It is expected that proper order reactors implement:
 * - `_initiate`. To convert partially structured orders into order keys that describe fulfillment conditions.
 * - `_resolveKey`. Helper function to convert an order into an order key.
 * You can find more information about these in ./helpers/ResolverAbstractions.sol
 * @dev Important implementation quirks:
 * **Token Trust**
 * There is a lot of trust put into the tokens that interact with the contract. Not trust as in the tokens can
 * impact this contract but trust as in a faulty / malicious token may be able to break the order status flow
 * and prevent proper delivery of inputs (to solver) and return of collateral.
 * As a result, it is important that users are aware of the following usage restrictions:
 * 1. Don't use a pausable/blacklist token if there is a risk that one of the actors (user / solver)
 * being paused. This also applies from the user's perspective, if a pausable token is used for
 * collateral their inputs may not be returnable.
 * 2. All inputs have to be trusted by all parties. If one input is unable to be transferred, the whole lot
 * becomes stuck until the issue is resolved.
 * 3. Solvers should validate that they can fill the outputs otherwise their collateral may be at risk and it could
 * annoy users.
 */
contract CatalystCompactReactor is BaseReactor {

    ITheCompactClaims public immutable COMPACT;

    constructor(address compact) {
        COMPACT = ITheCompactClaims(compact);
    }


    // /**
    //  * @notice Initiates a cross-chain order
    //  * @dev Called by the filler. Before calling, please check if someone else has already initiated.
    //  * The check if an order has already been initiated is late and may use a lot of gas.
    //  * When a filler initiates a transaction it is important that they do the following:
    //  * 1. Trust the reactor. Technically, anyone can deploy a reactor that takes these interfaces.
    //  * As the filler has to provide collateral, this collateral could be at risk.
    //  * 2. Verify that the deadlines provided in the order are sane. If proof - challenge is small
    //  * then it may impossible to prove thus free to challenge.
    //  * 3. Trust the oracles. Any oracles can be provided but they may not signal that the proof
    //  * is or isn't valid.
    //  * 4. Verify all inputs & outputs. If they contain a token the filler does not trust, do not claim the order.
    //  * It may cause a host of problem but most importantly: Inability to payout inputs & Inability to payout collateral.
    //  * 5. If fillDeadline == challengeDeadline && challengerCollateralAmount == 0, then the order REQUIRES a proof
    //  * and the user will be set as the default challenger.
    //  * @param order The CrossChainOrder definition
    //  * @param signature The end user signature for the order
    //  * If an order has already been deposited, the signature is ignored.
    //  * @param fillerData Any filler-defined data required by the settler
    //  */
    function openFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata signature,
        bytes calldata originFllerData
    ) external {
    }

    /**
     * @notice Prove that an order was filled. Requires that the order oracle exposes
     * a function, isProven(...), that returns true when called with the order details.
     * @dev If an order has configured some additional data that should be executed on
     * initiation, then this has to be provided here as executionData. If the executionData
     * is lost, then the filler should call `modifyOrderFillerdata` to set new executionData.
     * If you are calling this function from an external contract, beaware of re-entry
     * issues from a later execute. (configured of executionData).
     */
    /**
     * @notice This function is step 1 to initate a user's deposit.
     * It deposits the assets required for ´order´ into The Compact.
     */
     // TODO: get rid of btyes here
    function open(GaslessCrossChainOrder calldata order, bytes calldata asig, bytes calldata ssig) external {
        _validateOrder(order);

        // Decode the order data.
        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));

        bytes32 orderId = _orderIdentifier(order);

        address solvedBy = _outputsFilled(orderData.localOracle, orderId, orderData.outputs);

        // Payout inputs.
        _resolveLock(
            order, asig, ssig, solvedBy
        );

        // bytes32 identifier = orderContext.identifier;
        // if (identifier != bytes32(0)) FillerDataLib.execute(identifier, orderHash, orderKey.inputs, executionData);

        emit Open(orderId, _resolve(order, msg.sender));
    }

    //--- The Compact & Resource Locks ---//

    function _resolveLock(GaslessCrossChainOrder calldata order, bytes calldata allocatorSignature, bytes calldata sponsorSignature, address solvedBy) internal virtual {

        CatalystOrderData memory orderData = abi.decode(order.orderData, (CatalystOrderData));

        uint256 numInputs = orderData.inputs.length;
        BatchClaimComponent[] memory claims = new BatchClaimComponent[](numInputs);
        InputDescription[] memory maxInputs = orderData.inputs;
        for (uint256 i; i < numInputs; ++i) {
            InputDescription memory input = orderData.inputs[i];
            claims[i] = BatchClaimComponent({
                id: input.tokenId, // The token ID of the ERC6909 token to allocate.
                allocatedAmount: maxInputs[i].amount, // The original allocated amount of ERC6909 tokens.
                amount: input.amount // The claimed token amount; specified by the arbiter.
            });
        }

        bool success = COMPACT.claim(BatchClaimWithWitness({
            allocatorSignature: allocatorSignature,
            sponsorSignature: sponsorSignature,
            sponsor: order.user,
            nonce: order.nonce,
            expires: order.openDeadline,
            witness: bytes32(0), // Hash of the witness data. // TODO:
            witnessTypestring: string(abi.encodePacked(
                // TODO: Provide GaslessCrossChainOrder
                order.orderDataType
            )),
            claims: claims,
            claimant: solvedBy
        }));
        require(success); // This should always be true.
    }
}
