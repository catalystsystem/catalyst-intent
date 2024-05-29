// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IOrderType } from "../interfaces/IOrderType.sol";
import { OrderDescription, OrderFill, OrderContext, Signature } from "../interfaces/Structs.sol";
import { OrderKeyLib } from "../libs/OrderKeyLib.sol";
import { Permit2Lib } from "../libs/Permit2Lib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

import { OrderClaimed, OrderFilled, OrderVerify, OptimisticPayout } from "../interfaces/Events.sol";

abstract contract ReactorBase {
    using SafeTransferLib for ERC20;
    using OrderKeyLib for OrderKey;
    using Permit2Lib for OrderKey;

    mapping(address owner => mapping(uint96 nonce => bool)) internal _nonces; 

    ISignatureTransfer public immutable PERMIT2;

    /** @notice Maps an orderkey hash to the relevant orderContext. */
    mapping(bytes32 orderKeyHash => OrderContext orderContext) internal _orders; 

    constructor(permit2) {
        PERMIT2 = ISignatureTransfer(permit2);
    }

    // TODO: Do we also want to set execution time here?
    mapping(bytes32 orderFillHash => bytes32 fillerIdentifier) public filledOrders;

    error OrderClaimed(OrderContext orderContext);
    error WrongOrderStatus(OrderStatus actual);
    error NonceClaimed();
    error NotOracle();
    error ChallangeDeadlinePassed();
    error OrderAlreadyChallanged();
    error ProofPeriodHasNotPassed();
    error OrderNotReadyForOptimisticPayout();

    //--- Expose Storage ---//

    function orderKeyHash(OrderKey calldata orderKey) external returns(bytes32) {
        return orderKey.hash();
    }

    function order(OrderKey calldata orderKey) external returns(OrderContext orderContext) {
        return orderContext = _orders[orderKey.hash()];
    }

    function nonces(address owner, uint96 nonce) external returns(bool) {
        return _nonces[owner][nonce];
    }

    //--- Token Handling ---//

    function _collectTokens(OrderKey memory orderKey) internal override {

    }

    //--- Order Handling ---//

    /**
     * @notice Sets a nonce to executed to invalidate any attempt to claim the nonce.
     */
    function invalidateNonce(uint96 nonce) external {
        _nonces[msg.sender][nonce] = true;
    }

    function _orderKeyValidation(OrderKey memory orderKey) internal {
        // We don't have to check that we are on the correct chain, since this is implicit when we verify the signature of the order.
        if (uint48(block.timestamp) > order.reactorContext.fillByDeadline) revert OrderTimedOut(uint48(block.timestamp), order.reactorContext.fillByDeadline);

        // TODO: Collateral if (msg.value < order.minBond) revert BondTooSmall(msg.value, order.minBond);
    }

    /**
     * @notice Relevant claiming logic associated with orders.
     */
    function _claim(OrderKey memory orderKey, address filler) internal {
        // 0. Check the context of the order is valid.
        _orderKeyValidation(orderKey);

        // (The following 2 checks act as soft local reentry protections.)

        // 1. Check if the nonce has been claimed before.
        bool claimed = _nonce[orderKey.owner][orderKey.nonce];
        if (claimed) revert NonceClaimed();
        _nonce[orderKey.owner][orderKey.nonce] = true;

        // 2. Set the storage.
        OrderContext storage orderContext = _orders[order.hash()];
        if (orderContexet.status != OrderStatus.Unfilled) revert OrderClaimed(orderContext);
        orderContext.status == OrderContext.claimed;
        orderContext.filler = filler;

        // 3. Collect tokens from the user.
        // TODO:

        // The implementating contract is responsible for emitting the relevant order context.
    }

    //--- Order Resolution Helpers ---//

    function oracle(OrderKey calldata orderKey) external {
        OrderContext storage orderContext = _orders[orderKey.hash()];

        // Check if sender is oracle
        if (OrderKey.oracle != msg.sender) revert NotOracle();

        OrderStatus status = orderContext.status;

        // Only allow processing if order status is either claimed or Challenged
        if (
            status != OrderStatus.Claimed &&
            status != OrderStatus.Challenged
        ) revert WrongOrderStatus(orderContext.status);
        
        // Set order status to filled.
        orderContext.status = OrderStatus.Filled;

        // Payout input.
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
        // Check if someone challanged this order.
        if (status == OrderStatus.Challenged && orderContext.challanger != address(0)) {
            uint256 challangerCollateralAmount = orderKey.collateral.challangerCollateralAmount;
            ERC20(collateralToken).safeTransfer(filler, challangerCollateralAmount);
        }
    }

    /**
     * @dev Anyone can call this but the payout goes to the designated claimer.
     */
    function optimisticPayout(OrderKey calldata orderKey) external payable returns(uint256 sourceAmount) {
        OrderContext storage orderContext = _orders[orderKey.hash()];

        // Check if order is challanged:
        if (orderContext.status != OrderStatus.Claimed) revert WrongOrderStatus(orderContext.status);
        orderContext.status = OrderStatus.OPFilled;

        // Check if time is post challange deadline
        uint40 challangeDeadline = orderKey.reactorContext.challangeDeadline;
        if (uint40(block.timestamp) > challangeDeadline) revert OrderNotReadyForOptimisticPayout();

        address filler = orderContext.filler;
        // Get input tokens.
        address sourceAsset = orderKey.inputToken;
        inputAmount = orderKey.inputAmount;

        // Pay input tokens
        ERC20(sourceAsset).safeTransfer(filler, inputAmount);

        // Get order collateral.
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;

        // Pay collateral tokens
        ERC20(collateralToken).safeTransfer(filler, fillerCollateralAmount);

        emit OptimisticPayout(
            orderHash
        );
    }

    //--- Disputes ---//

    /**
     * @notice Disputes a claim.
     */
    function dispute(OrderKey calldata orderKey) external payable {
        OrderContext storage orderContext = _orders[orderKey.hash()];

        // Check that the order hasn't been challanged already.
        if (orderContext.status != OrderStatus.claimed) revert WrongOrderStatus(orderContext.status);
        if (orderContext.challanger == address(0)) revert OrderAlreadyChallanged();

        // Check if challange deadline hasn't been passed.
        if (orderKey.reactorContext.challangeDeadline > uint40(block.timestamp)) revert ChallangeDeadlinePassed();

        orderContext.status = OrderStatus.Challenged;
        orderContext.challanger = msg.sender;

        // Collect bond collateral.
        ERC20(orderKey.collateral.collateralToken).safeTransferFrom(msg.sender, address(this), orderKey.collateral.challangerCollateralAmount);
    }

    /**
     * @notice Finalise the dispute.
     */
    function completeDispute(OrderKey calldata orderKey) external {
        OrderContext storage orderContext = _orders[orderKey.hash()];

        // Check that the order is currently challanged
        if (orderContext.status != OrderStatus.Challenged) revert WrongOrderStatus(orderContext.status);
        if (orderContext.challanger != address(0)) revert OrderAlreadyChallanged();

        // Check if proof deadline has passed.
        if (orderKey.reactorContext.proofDeadline > uint40(block.timestamp)) revert ProofPeriodHasNotPassed();
        
        orderContext.status = OrderStatus.Fraud;

        // Get input tokens.
        address sourceAsset = orderKey.inputToken;
        inputAmount = orderKey.inputAmount;
        // Get order collateral.
        address collateralToken = orderKey.collateral.collateralToken;
        uint256 fillerCollateralAmount = orderKey.collateral.fillerCollateralAmount;
        uint256 challangerCollateralAmount = orderKey.collateral.challangerCollateralAmount;

        address owner = orderKey.owner;

        // Send inputs assets back to the user.
        ERC20(sourceAsset).safeTransfer(owner, inputAmount);

        // Send partical collateral back to user
        uint256 ownerCollateralAmount = fillerCollateralAmount/2;
        ERC20(collateralToken).safeTransfer(owner, ownerCollateralAmount);

        // Send the rest to the wallet that proof fraud:
        ERC20(collateralToken).safeTransfer(orderContext.challanger, fillerCollateralAmount - ownerCollateralAmount);
    }
}
