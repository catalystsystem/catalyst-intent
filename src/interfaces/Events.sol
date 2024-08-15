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

event OrderFilled(bytes32 indexed orderHash, address indexed fillerIdentifier, bytes32[] remoteOracles);

event OrderVerify(bytes32 indexed orderHash, bytes32 fillOrderHash);

event OptimisticPayout(bytes32 indexed orderHash);

event OrderChallenged(bytes32 indexed orderHash, address disputer);

event FraudAccepted(bytes32 indexed orderHash);

event OrderPurchased(bytes32 indexed orderHash, address indexed newFiller);

event GovernanceFeeChanged(uint256 oldGovernanceFee, uint256 newGovernanceFee);

event OrderPurchaseDetailsModified(bytes32 indexed orderHash, uint32 newPurchaseDeadline, uint16 newOrderDiscount);
