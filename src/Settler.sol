// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC20 } from 'solmate/tokens/ERC20.sol';
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IOrderType } from "./interfaces/IOrderType.sol";
import { OrderDescription, OrderFill, OrderContext, Signature } from "./interfaces/Structs.sol";

import { OrderClaimed } from "./interfaces/Events.sol";

contract Settler {
    using SafeTransferLib for ERC20;

    mapping(bytes32 orderHash => OrderContext orderContext) public claimedOrders; 
    mapping(bytes32 orderFillHash => address filler) public filledOrders;

    error IncorrectSourceChain(bytes32 actual, bytes32 order);
    error OrderTimedOut(uint64 timestamp, uint64 orderTimeout);
    error BondTooSmall(uint256 given, uint256 orderMinimum);

    bytes32 immutable SOURCE_CHAIN;

    constructor(bytes32 source_chain) {
        SOURCE_CHAIN = source_chain;
    }

    function _getOrderHash(OrderDescription calldata order) internal pure returns(bytes32 orderHash) {
        return orderHash = keccak256(abi.encodePacked(
            order.destinationAccount,
            order.destinationChain,
            order.destinationAsset,
            order.sourceChain,
            order.sourceAsset,
            order.minBond,
            order.timeout,
            order.sourceEvaluationContract,
            order.evaluationContext
        ));
    }

    function _getOrderFillHash(OrderFill calldata orderFill) internal pure returns(bytes32 orderFillHash) {
        return orderFillHash = keccak256(abi.encodePacked(
            orderFill.orderHash,
            orderFill.sourceChain,
            orderFill.destinationChain,
            orderFill.destinationAccount,
            orderFill.destinationAsset,
            orderFill.destinationAmount,
            orderFill.timeout
        ));
    }

    function getOrderHash(OrderDescription calldata order) external pure returns(bytes32 orderHash) {
        return orderHash = _getOrderHash(order);
    }

    function _getOrderOwner(bytes32 orderHash, Signature calldata signature) internal pure returns (address orderOwner) {
        return orderOwner = ecrecover(orderHash, signature.v, signature.r, signature.s);
    }

    function getOrderOwner(bytes32 orderHash, Signature calldata signature) external pure returns(address orderOwner) {
        return orderOwner = _getOrderOwner(orderHash, signature);
    }
    
    /// @notice Called by a solver when they want to claim the order
    /// @dev Claming is needed since otherwise a user can signed an order and after the solver does the delivery they
    /// can transfer the assets such that when the confirmation arrives the user cannot pay.
    /// 
    function claimOrder(OrderDescription calldata order, Signature calldata signature) external payable returns(uint256 sourceAmount, uint256 destinationAmount) {
        // Check that this is the appropiate source chain.
        if (SOURCE_CHAIN != order.sourceChain) revert IncorrectSourceChain(SOURCE_CHAIN, order.sourceChain);
        // Check that the order hasn't expired.
        if (uint64(block.timestamp) > order.timeout) revert OrderTimedOut(uint64(block.timestamp), order.timeout);
        if (msg.value < order.minBond) revert BondTooSmall(msg.value, order.minBond);

        // Get order hash so we can check that the owner is correctly provided.
        bytes32 orderHash = _getOrderHash(order);
        // Get the order owner.
        address orderOwner = _getOrderOwner(orderHash, signature);

        // Evaluate the order.
        (sourceAmount, destinationAmount) = IOrderType(order.sourceEvaluationContract).evaluate(order.evaluationContext, order.timeout);

        // TODO: Store order.
        // TODO: Reentry protection.

        ERC20(order.sourceAsset).safeTransferFrom(orderOwner, address(this), sourceAmount);

        emit OrderClaimed(
            msg.sender,
            orderOwner,
            sourceAmount,
            destinationAmount,
            msg.value,
            orderHash
        );
    }

    // TODO: I don't think there is any realistic way to verify that the data belongs.
    // Since not all envs might have access to the same hashing functions, we can't hash
    // OrderDescription and check that it belong in orderHash. The best we can do is get all
    // arguments, hash everything and use it to set storage.
    function _fillOrder(OrderFill calldata orderFill) internal {
        ERC20(address(bytes20(orderFill.destinationAsset))).safeTransferFrom(msg.sender, address(bytes20(orderFill.destinationAccount)), orderFill.destinationAmount);
    }

    /// @notice Sends the verification to an AMB to the source chain.
    function _verifyOrder(OrderFill calldata orderFill) internal {
        
    }

    function fillOrder(OrderFill calldata orderFill) external {
        _fillOrder(orderFill);
        // TODO: save
    }

    function verifyOrder(OrderFill calldata orderFill) external {
        // TODO: load
        _verifyOrder(orderFill);
    }

    function fillAndVerify(OrderFill calldata orderFill) external {
        _fillOrder(orderFill);
        _verifyOrder(orderFill);
    }
}
