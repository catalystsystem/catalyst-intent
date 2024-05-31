// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IOrderType } from "../interfaces/IOrderType.sol";
import { OrderContext, OrderStatus, OrderContext, OrderStatus, OrderKey } from "../interfaces/Structs.sol";
import { ISettlementContract, CrossChainOrder, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { CrossChainOrderLib } from "../libs/CrossChainOrderLib.sol";
import { Permit2Lib } from "../libs/Permit2Lib.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { OrderClaimed, OrderFilled, OrderVerify, OptimisticPayout } from "../interfaces/Events.sol";

abstract contract ReactorBase is ISettlementContract {
    using SafeTransferLib for ERC20;
    using CrossChainOrderLib for CrossChainOrder;
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

    error OrderAlreadyClaimed(OrderContext orderContext);
    error WrongOrderStatus(OrderStatus actual);
    error NonceClaimed();
    error NotOracle();
    error ChallangeDeadlinePassed();
    error OrderAlreadyChallanged();
    error ProofPeriodHasNotPassed();
    error OrderNotReadyForOptimisticPayout();

    //--- Expose Storage ---//

    function orderHash(CrossChainOrder calldata order) external returns (bytes32) {
        return order.hash();
    }

    function getOrderContext(CrossChainOrder calldata order) external view returns (OrderContext memory orderContext) {
        return orderContext = _orders[order.hash()];
    }

    //--- Token Handling ---//

    // function _collectTokens(OrderKey memory orderKey) internal override {

    // }

    //--- Order Handling ---//

    /**
     * @notice Initiates the settlement of a cross-chain order
     * @dev To be called by the filler
     * @param order The CrossChainOrder definition
     * @param signature The swapper's signature over the order
     * @param fillerData Any filler-defined data required by the settler
     */
    function initiate(CrossChainOrder calldata order, bytes calldata signature, bytes calldata fillerData) external {
        // TODO: read from fillerData.
        address filler = msg.sender;
        // Order validation is checked on PERMIT2 call later. For now, let mainly validate that
        // this order hasn't been claimed before:
        // TODO: Overwrite hash
        OrderContext storage orderContext = _orders[order.hash()];
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
    function optimisticPayout(OrderKey calldata orderKey) external payable returns(uint256 sourceAmount) {
    //     OrderContext storage orderContext = _orders[orderKey.hash()];

    //     // Check if order is challanged:
    //     if (orderContext.status != OrderStatus.Claimed) revert WrongOrderStatus(orderContext.status);
    //     orderContext.status = OrderStatus.OPFilled;

    //     // Check if time is post challange deadline
    //     uint40 challangeDeadline = orderKey.reactorContext.challangeDeadline;
    //     if (uint40(block.timestamp) > challangeDeadline) revert OrderNotReadyForOptimisticPayout();

    //     address filler = orderContext.filler;
    //     // Get input tokens.
    //     address sourceAsset = orderKey.inputToken;
    //     inputAmount = orderKey.inputAmount;

    //     // Pay input tokens
    //     ERC20(sourceAsset).safeTransfer(filler, inputAmount);

    //     // Get order collateral.
    //     address collateralToken = orderKey.collateral.collateralToken;
    //     uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;

    //     // Pay collateral tokens
    //     ERC20(collateralToken).safeTransfer(filler, fillerCollateralAmount);

    //     emit OptimisticPayout(
    //         orderHash
    //     );
    }

    //--- Disputes ---//

    /**
     * @notice Disputes a claim.
     */
    function dispute(OrderKey calldata orderKey) external payable {
    //     OrderContext storage orderContext = _orders[orderKey.hash()];

    //     // Check that the order hasn't been challanged already.
    //     if (orderContext.status != OrderStatus.claimed) revert WrongOrderStatus(orderContext.status);
    //     if (orderContext.challanger == address(0)) revert OrderAlreadyChallanged();

    //     // Check if challange deadline hasn't been passed.
    //     if (orderKey.reactorContext.challangeDeadline > uint40(block.timestamp)) revert ChallangeDeadlinePassed();

    //     orderContext.status = OrderStatus.Challenged;
    //     orderContext.challanger = msg.sender;

    //     // Collect bond collateral.
    //     ERC20(orderKey.collateral.collateralToken).safeTransferFrom(msg.sender, address(this), orderKey.collateral.challangerCollateralAmount);
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
