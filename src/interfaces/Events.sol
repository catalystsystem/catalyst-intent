// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OrderKey } from "./Structs.sol";

/**
 * @notice An order has been initiated.
 */
event OrderInitiated(bytes32 indexed orderHash, address indexed caller, bytes filler, OrderKey orderKey);

/**
 * @notice An order has been proven and settled.
 */
event OrderProven(bytes32 indexed orderHash, address indexed prover);

/**
 * @notice An order has been optimistically resolved.
 */
event OptimisticPayout(bytes32 indexed orderHash);

/**
 * @notice An order has ben challenged.
 */
event OrderChallenged(bytes32 indexed orderHash, address indexed disputer);

/**
 * @notice A challenged order was not proven and enough time has passed
 * since it was challenged so it has been assumed no delivery was made.
 */
event FraudAccepted(bytes32 indexed orderHash);

/**
 * @notice An order has been purchased by someone else and the filler has changed.
 */
event OrderPurchased(bytes32 indexed orderHash, address newFiller);

/**
 * @notice Governance fee changed. This fee is taken of the inputs.
 */
event GovernanceFeeChanged(uint256 oldGovernanceFee, uint256 newGovernanceFee);

/**
 * @notice Governance fees has been distributed.
 */
event GovernanceFeesDistributed(address indexed to, address[] tokens, uint256[] collectedAmounts);

/**
 * @notice The order purchase details have been modified by the filler.
 */
event OrderPurchaseDetailsModified(bytes32 indexed orderHash, bytes fillerdata);

event MapMessagingProtocolIdentifierToChainId(bytes32 messagingProtocolIdentifier, uint32 chainId);

event OutputFilled(uint32 fillDeadline, address token, address recipient, uint256 amount, bytes32 calldataHash);

event OutputVerified(
    uint32 fillDeadline,
    bytes32 token,
    bytes32 recipient,
    uint256 amount,
    bytes32 calldataHash,
    bytes32 verificationContext
);

event OutputProven(uint32 fillDeadline, bytes32 outputHash);
