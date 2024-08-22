// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OrderKey } from "./Structs.sol";

/**
 * @notice An order has been initiated.
 */
event OrderInitiated(bytes32 indexed orderHash, address indexed filler, address caller, OrderKey orderKey);

event OrderProven(bytes32 indexed orderHash, address indexed fillerIdentifier);

event OrderVerify(bytes32 indexed orderHash, bytes32 fillOrderHash);

event OptimisticPayout(bytes32 indexed orderHash);

event OrderChallenged(bytes32 indexed orderHash, address indexed disputer);

event FraudAccepted(bytes32 indexed orderHash);

event OrderPurchased(bytes32 indexed orderHash, address indexed newFiller);

event GovernanceFeeChanged(uint256 oldGovernanceFee, uint256 newGovernanceFee);

event GovernanceFeesCollected(address indexed to, address[] tokens, uint256[] collectedAmounts);

event OrderPurchaseDetailsModified(
    bytes32 indexed orderHash,
    address newFillerAddress,
    uint32 newPurchaseDeadline,
    uint16 newOrderDiscount,
    bytes32 newIdentifier
);
