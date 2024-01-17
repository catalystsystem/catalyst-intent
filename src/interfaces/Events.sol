// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/**
 * @notice An order has been claimed.
 */
event OrderClaimed(
    address indexed claimer,
    address indexed orderOwner,
    uint256 sourceAmount,
    uint256 destiantionAmount,
    uint256 bond,
    bytes32 orderHash
);