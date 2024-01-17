// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/**
 * @notice An order has been claimed.
 */
event OrderClaimed(
    address indexed claimer,
    address indexed orderOwner,
    uint256 sourceAmount,
    bytes32 orderHash,
    bytes evaluationContext
);