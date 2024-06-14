// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IOrderType } from "../interfaces/IOrderType.sol";

import { IOracle } from "../interfaces/IOracle.sol";

import {
    CrossChainOrder,
    ISettlementContract,
    Input,
    Output,
    ResolvedCrossChainOrder
} from "../interfaces/ISettlementContract.sol";
import { OrderContext, OrderKey, OrderStatus } from "../interfaces/Structs.sol";
import { Permit2Lib } from "../libs/Permit2Lib.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import {
    ChallangeDeadlinePassed,
    NonceClaimed,
    NotOracle,
    OrderAlreadyChallanged,
    OrderAlreadyClaimed,
    OrderNotClaimed,
    OrderNotReadyForOptimisticPayout,
    ProofPeriodHasNotPassed,
    WrongOrderStatus
} from "../interfaces/Errors.sol";
import { OptimisticPayout, OrderChallenged, OrderClaimed, OrderFilled, OrderVerify } from "../interfaces/Events.sol";

abstract contract BaseReactor is ISettlementContract {
    using Permit2Lib for OrderKey;

    ISignatureTransfer public immutable PERMIT2;

    /**
     * @notice Maps an orderkey hash to the relevant orderContext.
     */
    mapping(bytes32 orderKeyHash => OrderContext orderContext) internal _orders;

    constructor(address permit2) {
        PERMIT2 = ISignatureTransfer(permit2);
    }

    // TODO: Do we also want to set execution time here?
    mapping(bytes32 orderFillHash => bytes32 fillerIdentifier) public filledOrders;

    //--- Expose Storage ---//

    // todo: Profile with seperate functions for memory and calldata
    function _orderKeyHash(OrderKey memory orderKey) internal pure returns (bytes32) {
        return keccak256(abi.encode(orderKey)); // TODO: Is it more efficient to do this manually?
    }

    //Can be used
    function getOrderKeyInfo(OrderKey calldata orderKey)
        internal
        returns (bytes32 orderKeyHash, OrderContext memory orderContext)
    {
        orderKeyHash = _orderKeyHash(orderKey);
        orderContext = _orders[orderKeyHash];
    }

    //TODO: Do we need this?, we already have oderHash function for CrossChainOrder in CrossChainOrderLib.sol
    function orderHash(CrossChainOrder calldata order) external pure returns (bytes32) {
        return _orderHash(order);
    }

    function _orderHash(CrossChainOrder calldata order) internal pure virtual returns (bytes32);

    // //TODO: Do we really need this? we get context from orderkey not CrossChainOrder
    // function getOrderContext(CrossChainOrder calldata order) external view returns (OrderContext memory orderContext) {
    //     return orderContext = _orders[_orderHash(order)];
    // }

    //--- Token Handling ---//

    // TODO: check these for memory to calldata
    function _collectTokens(
        OrderKey memory orderKey,
        address owner,
        bytes32 witness,
        string memory witnessTypeString,
        bytes calldata signature
    ) internal virtual {
        (
            ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,
            ISignatureTransfer.SignatureTransferDetails[] memory transferDetails
        ) = orderKey.toPermit(address(this));

        PERMIT2.permitWitnessTransferFrom(permitBatch, transferDetails, owner, witness, witnessTypeString, signature);
    }

    //--- Order Handling ---//

    /**
     * @notice Initiates the settlement of a cross-chain order
     * @dev To be called by the filler
     * @param order The CrossChainOrder definition
     * @param signature The swapper's signature over the order
     * @param fillerData Any filler-defined data required by the settler
     */
    function initiate(CrossChainOrder calldata order, bytes calldata signature, bytes calldata fillerData) external {
        // TODO: solve permit2 context
        (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString) = _initiate(order, fillerData);

        address filler = abi.decode(fillerData, (address));

        // Check that the order hasn't been claimed yet. We will then set the order status
        // so other can't claim it. This acts as a local reentry check.
        OrderContext storage orderContext = _orders[_orderKeyHash(orderKey)];
        if (orderContext.status != OrderStatus.Unfilled) revert OrderAlreadyClaimed(orderContext);
        orderContext.status = OrderStatus.Claimed;
        orderContext.filler = filler;

        _collectTokens(orderKey, order.swapper, witness, witnessTypeString, signature);
    }

    /**
     * @notice Reactor types needs to implement this function to initiate their orders.
     * Return an orderKey with the relevant information to solve for.
     * @dev This function shouldn't check if the signature is correct but instead return information
     * such that we can make a permit2 call.
     */
    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal virtual returns (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString);

    /**
     * @notice Resolves a specific CrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param order The CrossChainOrder definition
     * @param fillerData Any filler-defined data required by the settler
     * @return ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
     */
    function resolve(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) external view returns (ResolvedCrossChainOrder memory) {
        return _resolve(order, fillerData);
    }

    function _resolve(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal view virtual returns (ResolvedCrossChainOrder memory);

    /**
     * TODO: docs
     */
    function resolveKey(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) external view returns (OrderKey memory) {
        return _resolveKey(order, fillerData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal view virtual returns (OrderKey memory);

    function _deliverInputs(Input[] calldata inputs, address to) internal {
        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            Input calldata input = inputs[i];
            SafeTransferLib.safeTransfer(input.token, to, input.amount);
        }
    }

    //--- Order Resolution Helpers ---//

    // TODO: figure out correct inputs here.
    function oracle(OrderKey calldata orderKey) external {
        OrderContext storage orderContext = _orders[_orderKeyHash(orderKey)];

        OrderStatus status = orderContext.status;

        // Only allow processing if order status is either claimed or Challenged
        if (status != OrderStatus.Claimed && status != OrderStatus.Challenged) {
            revert WrongOrderStatus(orderContext.status);
        }

        // TODO: custom error // TODO: salting of outputs.
        if (
            !IOracle(orderKey.localOracle).isProven(
                orderKey.outputs, orderKey.reactorContext.fillByDeadline, orderKey.remoteOracle
            )
        ) {
            require(false, "CannotProveOrder()");
        }

        // Set order status to filled.
        orderContext.status = OrderStatus.Filled;

        // Payout input.
        address filler = orderContext.filler;
        _deliverInputs(orderKey.inputs, filler);

        // Pay collateral
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;

        // Check if someone challanged this order.
        if (status == OrderStatus.Challenged && orderContext.challanger != address(0)) {
            fillerCollateralAmount = orderKey.collateral.challangerCollateralAmount;
        }

        // Pay collateral tokens
        SafeTransferLib.safeTransfer(collateralToken, filler, fillerCollateralAmount);
    }

    /**
     * @dev Anyone can call this but the payout goes to the designated claimer.
     */
    function optimisticPayout(OrderKey calldata orderKey) external payable {
        bytes32 orderKeyHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderKeyHash];

        // Check if order is claimed:
        if (orderContext.status != OrderStatus.Claimed) revert OrderNotClaimed(orderContext);
        // Do we need this check here?
        if (orderContext.challanger == address(0)) revert OrderAlreadyChallanged(orderContext);
        orderContext.status = OrderStatus.OPFilled;

        // Check if time is post challange deadline
        uint40 challangeDeadline = orderKey.reactorContext.challangeDeadline;
        if (uint40(block.timestamp) > challangeDeadline) revert OrderNotReadyForOptimisticPayout();

        address filler = orderContext.filler;

        // Pay input tokens to filler.
        uint256 numInputTokens = orderKey.inputs.length;
        for (uint256 i; i < numInputTokens; ++i) {
            Input calldata input = orderKey.inputs[i];
            address sourceAsset = input.token;
            uint256 inputAmount = input.amount;

            // TODO: subtract gov fee?
            SafeTransferLib.safeTransfer(sourceAsset, filler, inputAmount);
        }

        // Get order collateral.
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;

        // Pay collateral tokens
        SafeTransferLib.safeTransfer(collateralToken, filler, fillerCollateralAmount);

        emit OptimisticPayout(orderKeyHash);
    }

    //--- Disputes ---//

    /**
     * @notice Disputes a claim.
     */
    function dispute(OrderKey calldata orderKey) external payable {
        bytes32 orderKeyHash = _orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderKeyHash];

        // Check if order is claimed and hasn't been challenged:
        if (orderContext.status != OrderStatus.Claimed) revert OrderNotClaimed(orderContext);
        if (orderContext.challanger == address(0)) revert OrderAlreadyChallanged(orderContext);

        // Check if challange deadline hasn't been passed.
        if (orderKey.reactorContext.challangeDeadline > uint40(block.timestamp)) revert ChallangeDeadlinePassed();

        orderContext.status = OrderStatus.Challenged;
        orderContext.challanger = msg.sender;

        // Collect bond collateral.
        SafeTransferLib.safeTransferFrom(
            orderKey.collateral.collateralToken,
            msg.sender,
            address(this),
            orderKey.collateral.challangerCollateralAmount
        );

        emit OrderChallenged(orderKeyHash, msg.sender);
    }

    /**
     * @notice Finalise the dispute.
     */
    function completeDispute(OrderKey calldata orderKey) external {
        //     OrderContext storage orderContext = _orders[orderKey.hash()];

        //     // Check that the order is currently challanged
        //     if (orderContext.status != OrderStatus.Challenged) revert WrongOrderStatus(orderContext.status);
        //     if (orderContext.challanger != address(0)) revert OrderAlreadyChallanged();

        //     // Check if proof deadline has passed.
        //     if (orderKey.reactorContext.proofDeadline > uint40(block.timestamp)) revert ProofPeriodHasNotPassed();

        //     orderContext.status = OrderStatus.Fraud;

        //     // Get input tokens.
        //     address sourceAsset = orderKey.inputToken;
        //     inputAmount = orderKey.inputAmount;
        //     // Get order collateral.
        //     address collateralToken = orderKey.collateral.collateralToken;
        //     uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;
        //     uint256 challangerCollateralAmount = orderKey.collateral.challangerCollateralAmount;

        //     address owner = orderKey.owner;

        //     // Send inputs assets back to the user.
        //     ERC20(sourceAsset).safeTransfer(owner, inputAmount);

        //     // Send partical collateral back to user
        //     uint256 ownerCollateralAmount = fillerCollateralAmount/2;
        //     ERC20(collateralToken).safeTransfer(owner, ownerCollateralAmount);

        //     // Send the rest to the wallet that proof fraud:
        //     ERC20(collateralToken).safeTransfer(orderContext.challanger, fillerCollateralAmount - ownerCollateralAmount);
    }
}
