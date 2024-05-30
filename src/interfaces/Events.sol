// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @notice An order has been claimed.
 */
event OrderClaimed(
    address indexed filler,
    bytes32 indexed owner,
    uint96 nonce,
    uint256 inputAmount,
    address inputToken,
    address oracle,
    bytes32 destinationChainIdentifier,
    bytes32 destinationAddress,
    uint256 amount
);

event OrderFilled(
    bytes32 indexed orderHash,
    bytes32 indexed fillerIdentifier,
    bytes32 fillOrderHash,
    bytes destiantionAsset,
    uint256 destiantionAmount
);

event OrderVerify(bytes32 indexed orderHash, bytes32 fillOrderHash);

event OptimisticPayout(bytes32 indexed orderHash);
