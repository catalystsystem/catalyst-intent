// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IOrderType } from "../interfaces/IOrderType.sol";
import { OrderContext, OrderStatus, OrderKey } from "../interfaces/Structs.sol";
import { ISettlementContract, CrossChainOrder, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { Permit2Lib } from "../libs/Permit2Lib.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { OrderClaimed, OrderFilled, OrderVerify, OptimisticPayout, OrderChallenged } from "../interfaces/Events.sol";
import {
    OrderNotClaimed,
    OrderAlreadyClaimed,
    WrongOrderStatus,
    NonceClaimed,
    NotOracle,
    ChallangeDeadlinePassed,
    OrderAlreadyChallanged,
    ProofPeriodHasNotPassed,
    OrderNotReadyForOptimisticPayout
} from "../interfaces/Errors.sol";

abstract contract BaseReactor is ISettlementContract {
    using SafeTransferLib for ERC20;
    // todo: using Permit2Lib for OrderKey;

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

    function orderKeyHash(OrderKey calldata orderKey) internal pure returns (bytes32) {
        return _orderKeyHash(orderKey);
    }

    // Most probably will not need to override the hashing mechanism and settle it here
    function _orderKeyHash(OrderKey calldata orderKey) internal pure virtual returns (bytes32);

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

    function _collectTokens(OrderKey memory orderKey) internal virtual {
        // PERMIT2.permitWitnessTransferFrom(permit, transferDetails, owner, witness, witnessTypeString, signature);
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
        address filler = abi.decode(fillerData, (address));
        // Order validation is checked on PERMIT2 call later. For now, let mainly validate that
        // this order hasn't been claimed before:
        // TODO: Overwrite hash
        OrderContext storage orderContext = _orders[_orderHash(order)];
        if (orderContext.status != OrderStatus.Unfilled) revert OrderAlreadyClaimed(orderContext);
        orderContext.status = OrderStatus.Claimed;
        orderContext.filler = filler;

        _initiate(order, signature, fillerData);
    }

    function _initiate(CrossChainOrder calldata order, bytes calldata signature, bytes calldata fillerData)
        internal
        virtual;

    /**
     * @notice Resolves a specific CrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param order The CrossChainOrder definition
     * @param fillerData Any filler-defined data required by the settler
     * @return ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
     */
    function resolve(CrossChainOrder calldata order, bytes calldata fillerData)
        external
        view
        returns (ResolvedCrossChainOrder memory)
    {
        return _resolve(order, fillerData);
    }

    function _resolve(CrossChainOrder calldata order, bytes calldata fillerData)
        internal
        view
        virtual
        returns (ResolvedCrossChainOrder memory);

    //--- Order Resolution Helpers ---//

    function oracle(OrderKey calldata orderKey) external {
        //     OrderContext storage orderContext = _orders[orderKey.hash()];

        //     // Check if sender is oracle
        //     if (OrderKey.oracle != msg.sender) revert NotOracle();

        //     OrderStatus status = orderContext.status;

        //     // Only allow processing if order status is either claimed or Challenged
        //     if (
        //         status != OrderStatus.Claimed &&
        //         status != OrderStatus.Challenged
        //     ) revert WrongOrderStatus(orderContext.status);

        //     // Set order status to filled.
        //     orderContext.status = OrderStatus.Filled;

        //     // Payout input.
        //     address filler = orderContext.filler;
        //     // Get input tokens.
        //     address sourceAsset = orderKey.inputToken;
        //     uint256 inputAmount = orderKey.inputAmount;

        //     // Pay input tokens
        //     ERC20(sourceAsset).safeTransfer(filler, inputAmount);

        //     // Get order collateral.
        //     address collateralToken = orderKey.collateral.collateralToken;
        //     uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;

        //     // Pay collateral tokens
        //     ERC20(collateralToken).safeTransfer(filler, fillerCollateralAmount);
        //     // Check if someone challanged this order.
        //     if (status == OrderStatus.Challenged && orderContext.challanger != address(0)) {
        //         uint256 challangerCollateralAmount = orderKey.collateral.challangerCollateralAmount;
        //         ERC20(collateralToken).safeTransfer(filler, challangerCollateralAmount);
        //     }
    }

    /**
     * @dev Anyone can call this but the payout goes to the designated claimer.
     */
    function optimisticPayout(OrderKey calldata orderKey) external payable returns (uint256 sourceAmount) {
        bytes32 orderKeyHash = orderKeyHash(orderKey);
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
        // Get input tokens.
        address sourceAsset = orderKey.inputToken;
        uint256 inputAmount = orderKey.inputAmount;

        // Pay input tokens
        ERC20(sourceAsset).safeTransfer(filler, inputAmount);

        // Get order collateral.
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;

        // Pay collateral tokens
        ERC20(collateralToken).safeTransfer(filler, fillerCollateralAmount);

        emit OptimisticPayout(orderKeyHash);

        return inputAmount;
    }

    //--- Disputes ---//

    /**
     * @notice Disputes a claim.
     */
    function dispute(OrderKey calldata orderKey) external payable {
        bytes32 orderKeyHash = orderKeyHash(orderKey);
        OrderContext storage orderContext = _orders[orderKeyHash];

        // Check if order is claimed and hasn't been challenged:
        if (orderContext.status != OrderStatus.Claimed) revert OrderNotClaimed(orderContext);
        if (orderContext.challanger == address(0)) revert OrderAlreadyChallanged(orderContext);

        // Check if challange deadline hasn't been passed.
        if (orderKey.reactorContext.challangeDeadline > uint40(block.timestamp)) revert ChallangeDeadlinePassed();

        orderContext.status = OrderStatus.Challenged;
        orderContext.challanger = msg.sender;

        // Collect bond collateral.
        ERC20(orderKey.collateral.collateralToken).safeTransferFrom(
            msg.sender, address(this), orderKey.collateral.challangerCollateralAmount
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
