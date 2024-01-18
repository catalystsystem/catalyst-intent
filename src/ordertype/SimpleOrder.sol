// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OrderType } from "./OrderType.sol";

contract SimpleOrder is OrderType {
    /// @notice Reads the source amount and destination amount straight from evaluation context.
    function evaluate(bytes calldata evaluationContext, uint64 /* timeout */) external pure returns (uint256 sourceAmount, uint256 destinationAmount) {
        (sourceAmount, destinationAmount) = abi.decode(evaluationContext, (uint256, uint256));
    }
}
