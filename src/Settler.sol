// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IOrderType } from "./interfaces/IOrderType.sol";
import { OrderDescription, OrderFill, OrderContext, Signature } from "./interfaces/Structs.sol";

import { OrderClaimed, OrderFilled, OrderVerify, OptimisticPayout } from "./interfaces/Events.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";

contract Settler is ICrossChainReceiver {
    using SafeTransferLib for ERC20;

    mapping(bytes32 orderHash => OrderContext orderContext) public claimedOrders; 

    // TODO: Do we also want to set execution time here?
    mapping(bytes32 orderFillHash => bytes32 fillerIdentifier) public filledOrders;

    error IncorrectSourceChain(bytes32 actual, bytes32 order);
    error OrderTimedOut(uint64 timestamp, uint64 orderTimeout);
    error BondTooSmall(uint256 given, uint256 orderMinimum);
    error OrderAlreadyFilled(bytes32 orderFillHash, bytes32 filler);
    error OrderAlreadyClaimed(bytes32 orderHash);
    error OrderDisputed();
    error NotReadyForPayout(uint256 current, uint256 read);

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
        // TODO: Better hashing algorithm. This cannot be understood by the user. We need to make sure the
        // hashing here can be read by a ui. Figure out what is best practise.
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

        // Evaluate the order. This is an external static call.
        (sourceAmount, destinationAmount) = IOrderType(order.sourceEvaluationContract).evaluate(order.evaluationContext, order.timeout);

        // The following lines act as a local reentry protection.

        // Get order hash so we can check that the owner is correctly provided.
        bytes32 orderHash = _getOrderHash(order);
        // Ensure that the orderHash has not been claimed already.
        if (claimedOrders[orderHash].claimer != address(0)) revert OrderAlreadyClaimed(orderHash);

        // When setting the order context, we need to ensure claimer is not address(0).
        // However, msg.sender is never address(0).
        claimedOrders[orderHash] = OrderContext({
            sourceAmount: sourceAmount,
            sourceAsset: order.sourceAsset,
            claimer: msg.sender,  
            relevantDate: uint64(0), // TODO
            disputed: false
        });

        // The above lines act as a local reentry protection.

        // Get the order owner.
        address orderOwner = _getOrderOwner(orderHash, signature);

        // Collect tokens from owner.
        ERC20(order.sourceAsset).safeTransferFrom(orderOwner, address(this), sourceAmount);

        emit OrderClaimed(
            orderHash,
            msg.sender,
            orderOwner,
            order.sourceAsset,
            sourceAmount,
            order.destinationChain,
            order.destinationAccount,
            order.destinationAsset,
            destinationAmount,
            msg.value
        );
    }

    /// @dev Anyone can call this but the payout goes to the designated claimer.
    function optimisticPayout(bytes32 orderHash) external payable returns(uint256 sourceAmount) {
        OrderContext storage orderContext = claimedOrders[orderHash];

        // TODO: how to read orderContext most efficiently?
        sourceAmount = orderContext.sourceAmount;
        address claimer = orderContext.claimer;
        address sourceAsset = orderContext.sourceAsset;
        uint64 relevantDate = orderContext.relevantDate;
        bool disputed = orderContext.disputed;

        // Check that the order wasn't disputed
        if(disputed) revert OrderDisputed();
        if(block.timestamp < relevantDate ) revert NotReadyForPayout(block.timestamp, relevantDate);

        // Otherwise, payout:
        ERC20(sourceAsset).safeTransfer(claimer, sourceAmount);

        emit OptimisticPayout(
            orderHash
        );
    }

    //--- Internal Orderfilling ---//

    function _fillOrder(OrderFill calldata orderFill, bytes32 fillerIdentifier) internal returns(bytes32 orderFillHash) {
        orderFillHash = _getOrderFillHash(orderFill);
        // Check if the order was already filled.
        if (filledOrders[orderFillHash] != bytes32(0)) 
            revert OrderAlreadyFilled(orderFillHash, filledOrders[orderFillHash]);

        // It wasn't filled, set the current filler.
        // This is self-reentry protection.
        filledOrders[orderFillHash] = fillerIdentifier;

        ERC20(address(bytes20(orderFill.destinationAsset))).safeTransferFrom(msg.sender, address(bytes20(orderFill.destinationAccount)), orderFill.destinationAmount);
    }

    /// @notice Sends the verification to an AMB to the source chain.
    function _verifyOrder(OrderFill calldata orderFill, bytes32 fillerIdentifier) internal {
        
    }

    //--- External Orderfilling ---//
    /// @notice Fill an order.
    /// @dev There is no way to check if the order information is correct.
    /// That is because 1. we don't know what the orderHash was computed with. For an Ethereum VM,
    /// it is very likely it was keccak256. However, for CosmWasm, Solana, or ZK-VMs it might be different.
    /// As a result, the best we can do is to hash orderFill here and use it to block other ful.fillments.
    function fillOrder(OrderFill calldata orderFill, bytes32 fillerIdentifier) external {
        bytes32 orderFillhash = _fillOrder(orderFill, fillerIdentifier);

        emit OrderFilled(
            orderFill.orderHash,
            fillerIdentifier,
            orderFillhash,
            orderFill.destinationAsset,
            orderFill.destinationAmount
        );
    }

    /// @notice Verify an order. Is used if the order is challanged on the source chain.
    function verifyOrder(OrderFill calldata orderFill) external {
        bytes32 orderFillHash = _getOrderFillHash(orderFill);

        bytes32 fillerIdentifier = filledOrders[orderFillHash];
        _verifyOrder(orderFill, fillerIdentifier);

        emit OrderVerify(
            orderFill.orderHash,
            orderFillHash
        );
    }

    /// @notice Fill and immediately verify an order.
    function fillAndVerify(OrderFill calldata orderFill, bytes32 fillerIdentifier) external {
        bytes32 orderFillHash = _fillOrder(orderFill, fillerIdentifier);

        emit OrderFilled(
            fillerIdentifier,
            orderFill.orderHash,
            orderFillHash,
            orderFill.destinationAsset,
            orderFill.destinationAmount
        );

        _verifyOrder(orderFill, fillerIdentifier);

        emit OrderVerify(
            orderFill.orderHash,
            orderFillHash
        );
    }

    //--- Cross Chain Messages ---//
    /**
     * @notice Handles the acknowledgement from the destination
     * @dev acknowledgement is exactly the output of receiveMessage except if receiveMessage failed, then it is error code (0xff or 0xfe) + original message.
     * If an acknowledgement isn't needed, this can be implemented as {}.
     * - This function can be called by someone else again! Ensure that if this endpoint is called twice with the same message nothing bad happens.
     * - If the application expects that the maxGasAck will be provided, then it should check that it got enough and revert if it didn't.
     * Otherwise, it is assumed that you didn't need the extra gas.
     * @param destinationIdentifier An identifier for the destination chain.
     * @param messageIdentifier A unique identifier for the message. The identifier matches the identifier returned when escrowed the message.
     * This identifier can be mismanaged by the messaging protocol.
     * @param acknowledgement The acknowledgement sent back by receiveMessage. Is 0xff if receiveMessage reverted.
     */
    function receiveAck(bytes32 destinationIdentifier, bytes32 messageIdentifier, bytes calldata acknowledgement) external pure {
        // TODO: Do Nothing?
    }

    /**
     * @notice receiveMessage from a cross-chain call.
     * @dev The application needs to check the fromApplication combined with sourceIdentifierbytes to figure out if the call is authenticated.
     * - If the application expects that the maxGasDelivery will be provided, then it should check that it got enough and revert if it didn't.
     * Otherwise, it is assumed that you didn't need the extra gas.
     * @return acknowledgement Information which is passed to receiveAck. 
     *  If you return 0xff, you cannot know the difference between Executed but "failed" and outright failed.
     */
    function receiveMessage(bytes32 sourceIdentifierbytes, bytes32 messageIdentifier, bytes calldata fromApplication, bytes calldata message) external returns(bytes memory acknowledgement) {
        // todo: verified payout.
        return acknowledgement = hex"";
    }
}
