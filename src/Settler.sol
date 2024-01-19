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

    // TODO: Do we also want to set execution time here?
    mapping(bytes32 orderFillHash => bytes32 fillerIdentifier) public filledOrders;

    error IncorrectSourceChain(bytes32 actual, bytes32 order);
    error OrderTimedOut(uint64 timestamp, uint64 orderTimeout);
    error BondTooSmall(uint256 given, uint256 orderMinimum);
    error OrderAlreadyFilled(bytes32 orderFillHash, bytes32 filler);

    bytes32 immutable SOURCE_CHAIN;

    constructor(bytes32 source_chain) {
        SOURCE_CHAIN = source_chain;
    }

    //--- Order Hashing ---//

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

    //--- Expose Hashing ---//
    // The reason 'public' isn't being used for the hashing functions is that it comes
    // with additional checks that increases the gas cost. As a result, the hashing
    // algorithms are cheaper internally but more expensive externally.

    function getOrderHash(OrderDescription calldata order) external pure returns(bytes32 orderHash) {
        return orderHash = _getOrderHash(order);
    }

     function getOrderFillHash(OrderFill calldata orderFill) external pure returns(bytes32 orderFillHash) {
        return orderFillHash = _getOrderFillHash(orderFill);
    }

    //--- Order Helper Functions ---//

    function _getOrderOwner(bytes32 orderHash, Signature calldata signature) internal pure returns (address orderOwner) {
        return orderOwner = ecrecover(orderHash, signature.v, signature.r, signature.s);
    }

    function getOrderOwner(bytes32 orderHash, Signature calldata signature) external pure returns(address orderOwner) {
        return orderOwner = _getOrderOwner(orderHash, signature);
    }

    //--- Solver Functions ---//
    
    /// @notice Called by a solver when they want to claim the order
    /// @dev Claming is needed since otherwise a user can signed an order and after
    /// the solver does the delivery they can transfer the assets such that when the 
    // confirmation arrives the user cannot pay.
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

        // Evaluate the order. This is an external static call.
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

    // TODO: which args?
    function optimisticPayout(OrderDescription calldata order) external payable returns(uint256 sourceAmount) {

    }

    //--- Internal Orderfilling ---//

    function _fillOrder(OrderFill calldata orderFill) internal {
        ERC20(address(bytes20(orderFill.destinationAsset))).safeTransferFrom(msg.sender, address(bytes20(orderFill.destinationAccount)), orderFill.destinationAmount);
    }

    /// @notice Sends the verification to an AMB to the source chain.
    function _verifyOrder(OrderFill calldata orderFill, bytes32 fillerIdentifier) internal {
        
    }

    //--- External Orderfilling ---//

    function _setFiller(OrderFill calldata orderFill, bytes32 fillerIdentifier) internal returns(bytes32 orderFillHash) {
        orderFillHash = _getOrderFillHash(orderFill);
        // Check if the order was already filled.
        if (filledOrders[orderFillHash] != bytes32(0)) 
            revert OrderAlreadyFilled(orderFillHash, filledOrders[orderFillHash]);

        // It wasn't filled, set the current filler.
        // This is self-reentry protection.
        filledOrders[orderFillHash] = fillerIdentifier;
    }

    /// @notice Fill an order.
    /// @dev There is no way to check if the order information is correct.
    /// That is because 1. we don't know what the orderHash was computed with. For an Ethereum VM,
    /// it is very likely it was keccak256. However, for CosmWasm, Solana, or ZK-VMs it might be different.
    /// As a result, the best we can do is to hash orderFill here and use it to block other ful.fillments.
    function fillOrder(OrderFill calldata orderFill, bytes32 fillerIdentifier) external {
        bytes32 orderFillhash = _setFiller(orderFill, fillerIdentifier);

        _fillOrder(orderFill);
    }

    /// @notice Verify an order. Is used if the order is challanged on the source chain.
    function verifyOrder(OrderFill calldata orderFill) external {
        bytes32 orderFillHash = _getOrderFillHash(orderFill);

        bytes32 fillerIdentifier = filledOrders[orderFillHash];
        _verifyOrder(orderFill, fillerIdentifier);
    }

    /// @notice Fill and immediately verify an order.
    function fillAndVerify(OrderFill calldata orderFill, bytes32 fillerIdentifier) external {
        bytes32 orderFillhash = _setFiller(orderFill, fillerIdentifier);

        _fillOrder(orderFill);

        _verifyOrder(orderFill, fillerIdentifier);
    }
}
