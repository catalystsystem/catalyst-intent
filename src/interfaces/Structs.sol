// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

enum OrderStatus {
    Unfilled,
    Claimed,
    Challenged,
    Fraud,
    OPFilled,
    Filled
}

struct OrderContext {
    OrderStatus status;
    address challanger;
    address filler;
}

struct ReactorInfo {
    // The contract that is managing this order.
    address reactor;
    
    // Order resolution times
    uint40 fillByDeadline;
    uint40 challangeDeadline;
    uint40 proofDeadline;
}

struct Collateral {
    address collateralToken; // TODO: Just use gas?
    uint256 fillerCollateralAmount;
    uint256 challangerCollateralAmount;
}

/**
 * @notice This is the simplified order after it has been validated and evaluated.
 * @dev 
 * - Validated: We check that the signature of the order matches the relevant order.
 * - Evaluated: The signed order has been evaluated for its respective inputs and outputs
 */
struct ResolvedOrder {
    // The contract that is managing this order.
    ReactorInfo reactorContext;

    // Who this order was claimed by.
    address owner;
    uint96 nonce;

    // Order inputs
    uint256 inputAmount;
    address inputToken;

    // Collateral
    Collateral collateral;

    // Destination chain context
    address oracle; // The oracle that can satisfy a dispute.
    bytes32 destinationChainIdentifier;
    bytes32 destinationAddress;
    uint256 amount;
}
