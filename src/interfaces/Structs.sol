// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

enum OrderStatus {
    Unfilled,
    Claimed,
    Filled,
    Challenged,
    Fraud
}

/// @notice The order description.
struct OrderDescription {
    // The address to evaluate the order. Also determines the type of the order.
    address orderType;
    // The account on the destination chain.
    // Encoding depends on the implementation, evm is abi.encodePacked().
    bytes destinationAccount;
    // Timestamp for when the order is invalid. // TODO: Should also be used to nonce the order?
    uint64 baseTimeout;
    // TODO: Include swapper address?
    // For: It would make all swap hashes unique.
    // Against: Not really needed since the recipitent should be the unique-ish. We can get the user from the signature.
    // address user;
    // Custom execution logic. Only on source chain.
    address postExecutionHook;
    // Payload for the hook.
    bytes postExecutionHookData;
}

struct CrossChainDescription {
    // Destination chain identifier. For EVM use block.chainid.
    bytes32 destinationChain;
    // The minimum bond required to collect the order.
    uint256 minBond;
    // Period in seconds that the solver has to fill the order. If it is not filled within this time
    // then the order can be challanged successfully => Once claimed, the solver has block.timestamp + fillTime to fill the order.
    uint32 fillPeriod;
    // Period in seconds once after fillTime when the order can be optimistically claimed => Once claimed, the order can be challanged for until block.timestamp + fillTime + challangeTime.
    uint32 challangePeriod;
    // Period in seconds after a challange has been submitted that the solver has to verify that they filled on the destination chain.
    // It is important that solver verify that this proof period is long enough to deliver proofs before taking orders.
    uint32 proofPeriod;
    // The AMBs that can be used to deliver proofs.
    address[] approvedAmbs; // TODO: Is there a better way to set allowed AMBS?
}

struct Asset {
    uint256 amount;
    address asset;
}

struct OrderFill {
    bytes32 orderHash;
    bytes32 sourceChain;
    bytes32 destinationChain;
    bytes destinationAccount;
    bytes destinationAsset;
    uint256 destinationAmount;
    uint64 timeout;
}

// Todo: compacting?
/// @param relevantDate Is used as the optimistic payout by date if disputed is false. If disputed is true it is the date when the proof has to be delivered by.
struct OrderContext {
    uint256 bond;
    uint256 sourceAmount;
    address sourceAsset;
    address orderOwner;
    address claimer;
    address disputer;
    uint64 relevantDate;
}

struct SignedOrder {
    bytes order;
    bytes signature;
}