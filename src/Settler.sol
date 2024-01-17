// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC20 } from 'solmate/tokens/ERC20.sol';
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IOrderType } from "./interfaces/IOrderType.sol";
import { OrderDescription, OrderContext, Signature } from "./interfaces/Structs.sol";

import { OrderClaimed } from "./interfaces/Events.sol";

contract Settler {
    using SafeTransferLib for ERC20;

    mapping(bytes32 orderHash => OrderContext orderContext) public claimedOrders; 
    mapping(bytes32 orderHash => uint256 fill) public filledOrders; 

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
            order.destinationEvaluationContract,
            order.evaluationContext
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
    
    function claimOrder(OrderDescription calldata order, Signature calldata signature, uint256 doubleBond) external returns(uint256 sourceAmount, uint256 destinationAmount) {
        // Check that this is the appropiate source chain.
        if (SOURCE_CHAIN != order.sourceChain) revert IncorrectSourceChain(SOURCE_CHAIN, order.sourceChain);
        // Check that the order hasn't expired.
        if (uint64(block.timestamp) > order.timeout) revert OrderTimedOut(uint64(block.timestamp), order.timeout);
        if (doubleBond < order.minBond) revert BondTooSmall(doubleBond, order.minBond);

        // Get order hash so we can check that the owner is correctly provided.
        bytes32 orderHash = _getOrderHash(order);
        // Get the order owner.
        address orderOwner = _getOrderOwner(orderHash, signature);

        // Evaluate the order.
        (sourceAmount, destinationAmount) = IOrderType(order.sourceEvaluationContract).evaluate(order.evaluationContext, order.timeout);

        // TODO: Store order.
        // TODO: Reentry protection.

        ERC20(order.sourceAsset).safeTransferFrom(orderOwner, address(this), sourceAmount);

        // TODO: Collect bond.

        emit OrderClaimed(
            msg.sender,
            orderOwner,
            sourceAmount,
            destinationAmount,
            doubleBond,
            orderHash
        );
    }

    function fillOrder(bytes32 orderHash, bytes calldata destinationAccount, bytes calldata destinationAsset, uint256 destinationAmount ) external {
        ERC20(address(bytes20(destinationAsset))).safeTransferFrom(msg.sender, address(bytes20(destinationAccount)), destinationAmount);
    }
}
