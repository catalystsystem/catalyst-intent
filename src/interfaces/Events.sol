// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/**
 * @notice An order has been claimed.
 */
event OrderClaimed(
    bytes32 indexed orderHash,
    address indexed claimer,
    address indexed orderOwner,
    address sourceAsset,
    uint256 sourceAmount,
    bytes32 destinationChain,
    bytes destinationAccount,
    bytes destinationAsset,
    uint256 destiantionAmount,
    uint256 bond
);

event OrderFilled(
    bytes32 indexed orderHash,
    bytes32 indexed fillerIdentifier,
    bytes32 fillOrderHash,
    bytes destiantionAsset,
    uint256 destiantionAmount
);

event OrderVerify(
    bytes32 indexed orderHash,
    bytes32 fillOrderHash
);

event OptimisticPayout(
    bytes32 indexed orderHash
);