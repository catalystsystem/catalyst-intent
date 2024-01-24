// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OrderDescription, CrossChainDescription, Asset } from "../interfaces/Structs.sol";
import { OrderType } from "./OrderType.sol";

struct SimpleOrder {
    // The description of the order is first such that we can reliably decode OrderDescription.orderType.
    OrderDescription orderDescription;
    // The description of to go cross-chain.
    CrossChainDescription crossChainDescription;
    
    // Relevant context for this order type.
    Asset[] inputs;
    Asset[] outputs;
}

contract SimpleOrderType is OrderType {
    // string internal constant    

    function _decodeEvaluationContext(bytes calldata evaluationContext) internal pure returns(SimpleOrderContext memory simpleOrderContext) {
        simpleOrderContext = abi.decode(evaluationContext, (SimpleOrderContext));
    }

    function decodeEvaluationContext(bytes calldata evaluationContext) external pure returns(SimpleOrderContext memory simpleOrderContext) {
        simpleOrderContext = _decodeEvaluationContext(evaluationContext);
    }

    /// @notice Reads the source amount and destination amount straight from evaluation context.
    function evaluate(bytes calldata evaluationContext, uint64 /* timeout */) external pure returns (uint256 sourceAmount, uint256 destinationAmount) {
        SimpleOrderContext memory simpleOrderContext = abi.decode(evaluationContext, (SimpleOrderContext));
    }


    function _hash(SimpleOrder memory order) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked())
    }
}
