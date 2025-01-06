// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IOracle } from "../interfaces/IOracle.sol";

import { IsContractLib } from "../libs/IsContractLib.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    IOriginSettler,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "../interfaces/IERC7683.sol";



import { CatalystOrderData, InputDescription, OutputDescription } from "../libs/CatalystOrderType.sol";

import {
    InvalidSettlementAddress,
    WrongChain,
    InitiateDeadlinePassed,
    CannotProveOrder
} from "../interfaces/Errors.sol";

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
contract BaseReactor {
    bytes32 public constant VERSION_FLAGS = bytes32(uint256(2));

    //--- Hashing Orders ---//

    // TODO: Make a proper hashing function.
    function _orderIdentifier(GaslessCrossChainOrder calldata order) pure internal returns(bytes32) {
        return keccak256(abi.encode(order));
    }

    function orderIdentifier(GaslessCrossChainOrder calldata order) pure external returns(bytes32) {
        return _orderIdentifier(order);
    }

    //--- Order Validation ---//

    function _validateOrder(GaslessCrossChainOrder calldata order) internal view {
        // Check that we are the settler for this order:
        if (address(this) != order.originSettler) revert InvalidSettlementAddress();
        // Check that this is the right originChain
        if (block.chainid != order.originChainId) revert WrongChain(block.chainid, order.originChainId);
        // Check if the open deadline has been passed
        if (block.timestamp > order.openDeadline) revert InitiateDeadlinePassed();
    }

    function _outputsFilled(address localOracle, bytes32 orderId, OutputDescription[] memory outputs) view internal returns (address solvedBy) {
        // The following call is a external call to an untrusted contract.
        solvedBy = IOracle(localOracle).outputFilled(orderId, outputs);
        if (solvedBy == address(0)) revert CannotProveOrder();
    }

    //--- Order Handling ---//


    //--- Order Purchase Helpers ---//

    // /**
    //  * @notice This function is called from whoever wants to buy an order from a filler and gain a reward
    //  * @dev If you are buying a challenged order, ensure that you have sufficient time to prove the order or
    //  * your funds may be at risk.
    //  * Set newPurchaseDeadline in the past to disallow future takeovers.
    //  * When you purchase orders, make sure you take into account that you are paying the
    //  * entirety while you will get out the entirety MINUS any governance fee.
    //  * If you are calling this function from an external contract, beaware of re-entry
    //  * issues from a later execute. (configured of fillerData).
    //  * @param orderKey Claimed order to be purchased from the filler.
    //  * @param fillerData New filler data + potential execution data post-pended.
    //  * @param minDiscount The minimum discount the new filler is willing to buy at.
    //  * Should be set to disallow someone frontrunning this call and decreasing the discount.
    //  */
    // function purchaseOrder(OrderKey calldata orderKey, bytes calldata fillerData, uint256 minDiscount) external {
    //     bytes32 orderKeyHash = _orderKeyHash(orderKey);
    //     OrderContext storage orderContext = _orders[orderKeyHash];

    //     {
    //         OrderStatus status = orderContext.status;

    //         // The order should have been claimed and not paid / proven / fraud proven (inputs should be intact)
    //         // for it to be purchased.
    //         if (status != OrderStatus.Claimed && status != OrderStatus.Challenged) {
    //             revert WrongOrderStatus(orderContext.status);
    //         }
    //     }

    //     // The order cannot be purchased after the max time specified to be sold at has passed
    //     if (orderContext.orderPurchaseDeadline < block.timestamp) {
    //         revert PurchaseTimePassed();
    //     }

    //     // Decode filler data.
    //     // (
    //     //     address fillerAddress,
    //     //     uint32 orderPurchaseDeadline,
    //     //     uint16 orderPurchaseDiscount,
    //     //     bytes32 identifier,
    //     //     uint256 fillerDataPointer
    //     // ) = FillerDataLib.decode(fillerData);

    //     // Load old storage variables.
    //     address oldFillerAddress = orderContext.fillerAddress;
    //     uint16 oldOrderPurchaseDiscount = orderContext.orderPurchaseDiscount;
    //     bytes32 oldIdentifier = orderContext.identifier;
    //     // Check if the discount is good. Remember that a larger number is a better discount.
    //     if (minDiscount > oldOrderPurchaseDiscount) {
    //         revert MinOrderPurchaseDiscountTooLow(minDiscount, oldOrderPurchaseDiscount);
    //     }

    //     // We can now update the storage with the new filler data.
    //     // This allows us to avoid reentry protecting this function.
    //     orderContext.fillerAddress = fillerAddress;
    //     orderContext.orderPurchaseDeadline = orderPurchaseDeadline;
    //     orderContext.orderPurchaseDiscount = orderPurchaseDiscount;
    //     orderContext.identifier = identifier;

    //     // We can now make external calls without allowing local reentries into this call.

    //     // Collateral is paid for in full.
    //     address collateralToken = orderKey.collateral.collateralToken;
    //     uint256 collateralAmount = orderKey.collateral.fillerCollateralAmount;
    //     // No need to check if collateral is valid, since it has already entered the contract.
    //     if (collateralAmount > 0) SafeTransferLib.safeTransferFrom(collateralToken, msg.sender, oldFillerAddress, collateralAmount);

    //     // Transfer the ERC20 tokens. This requires explicit approval for this contract for each token.
    //     // This is not done through permit.
    //     // This function assumes the collection is from msg.sender, as a result we don't need to specify that.
    //     _collectTokensFromMsgSender(orderKey.inputs, oldFillerAddress, oldOrderPurchaseDiscount);

    //     // Check if there is an identifier, if there is execute data.
    //     if (oldIdentifier != bytes32(0)) {
    //         // FillerDataLib.execute(identifier, orderKeyHash, orderKey.inputs, fillerData[fillerDataPointer:]);
    //     }

    //     emit OrderPurchased(orderKeyHash, msg.sender);
    // }


    //--- The Compact & Resource Locks ---//

    

    //--- ERC7683 Resolvers ---//

    /**
     * @notice Resolves an order into an ERC-7683 compatible order struct.
     * By default relies on _resolveKey to convert OrderKey into a ResolvedCrossChainOrder
     * @dev Can be overwritten if there isn't a translation of an orderKey into resolvedOrder.
     * @param order CrossChainOrder to resolve.
     * @param  filler The filler of the order
     * @return resolvedOrder ERC-7683 compatible order description, including the inputs and outputs of the order
     */
    function _resolve(
        GaslessCrossChainOrder calldata order,
        address filler
    ) internal view virtual returns (ResolvedCrossChainOrder memory resolvedOrder) {
        CatalystOrderData memory orderData = abi.decode(order.orderData, (CatalystOrderData));

        uint256 numOutputs = orderData.outputs.length;
        Output[] memory maxSpent = new Output[](numOutputs);
        
        // If the output list is sorted by chains, this list is unqiue and optimal.
        FillInstruction[] memory fillInstructions = new FillInstruction[](numOutputs);
        for (uint256 i = 0; i < numOutputs; ++i) {
            OutputDescription memory catalystOutput = orderData.outputs[i];
            uint256 chainId = catalystOutput.chainId;
            maxSpent[i] = Output({
                token: catalystOutput.token,
                amount: catalystOutput.amount,
                recipient: catalystOutput.recipient,
                chainId: chainId
            });
            fillInstructions[i] = FillInstruction({
                destinationChainId: uint64(chainId),
                destinationSettler: catalystOutput.remoteOracle,
                originData: abi.encode(catalystOutput)
            });
        }

        // fillerOutputs are of the Output type and as a result, we can't just
        // load swapperInputs into fillerOutputs. As a result, we need to parse
        // the individual inputs and make a new struct.
        uint256 numInputs = orderData.inputs.length;
        Output[] memory minReceived = new Output[](numInputs);
        unchecked {
            for (uint256 i; i < numInputs; ++i) {
                InputDescription memory input = orderData.inputs[i];
                minReceived[i] = Output({
                    token: bytes32(uint256(uint160(input.tokenId))),
                    amount: input.amount,
                    recipient: bytes32(uint256(uint160(filler))),
                    chainId: uint32(block.chainid)
                });
            }
        }


        // Lastly, complete the ResolvedCrossChainOrder struct.
        resolvedOrder = ResolvedCrossChainOrder({
            user: order.user,
            originChainId: order.originChainId,
            openDeadline: order.openDeadline,
            fillDeadline: order.fillDeadline,
            orderId: _orderIdentifier(order),
            maxSpent: maxSpent,
            minReceived: minReceived,
            fillInstructions: fillInstructions
        });
    }

    /**
     * @notice ERC-7683: Resolves a specific CrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param order CrossChainOrder to resolve.
     * @param fillerData Any filler-defined data required by the settler
     * @return resolvedOrder ERC-7683 compatible order description, including the inputs and outputs of the order
     */
    function resolve(
        OnchainCrossChainOrder calldata order,
        bytes calldata fillerData
    ) external view returns (ResolvedCrossChainOrder memory resolvedOrder) {
        // return _resolve(order, fillerData);
    }

    function resolveFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata /* signature */,
        bytes calldata originFllerData
    ) external view returns (ResolvedCrossChainOrder memory resolvedOrder) {
        return _resolve(order, abi.decode(originFllerData, (address)));
    }
}
