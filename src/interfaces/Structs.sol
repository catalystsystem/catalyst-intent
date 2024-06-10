// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Input, Output } from "./ISettlementContract.sol";

//////////////////
// Order types ///
//////////////////

/**
 * @notice The progressive order status of cross-chain orders
 *
 * - Unfilled: Default state. Progresses to Claimed.
 * - Claimed: A solver has claimed this order. Progresses to Challanged or OPFilled.
 * - Challenged: A claimed order was challenged. Progresses to Fraud or Proven.
 * - Fraud: The solver did not prove delivery & Challenger claiemd the collateral. Final.
 * - OPFilled: A claimed order was not challenged. Payed inputs to solver. Final.
 * - Proven: A solver proved settlement. Progresses to Filled.
 * - Filled: A proven settlement was paid. Final.
 */
enum OrderStatus {
    Unfilled,
    Claimed,
    Challenged,
    Fraud,
    OPFilled,
    Proven,
    Filled
}

struct OrderContext {
    OrderStatus status;
    address challanger;
    address filler;
}

/**
 * @notice This is the simplified order after it has been validated and evaluated.
 * @dev
 * - Validated: We check that the signature of the order matches the relevant order.
 * - Evaluated: The signed order has been evaluated for its respective inputs and outputs
 */
struct OrderKey {
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
    address localOracle; // The oracle that can satisfy a dispute.
    bytes32 destinationChainIdentifier;
    address remoteOracle;
    bytes32 oracleProofHash;
    // Contains the below:
    // TODO: Figure out what is a good strucutre for how to generalise the destination target.
    bytes32 destinationAsset; // TODO: Is this a waste? Can we use this better?
    bytes32 destinationAddress; // TODO bytes? For better future compatability?
    uint256 amount;

    bytes inputs; // abi.encode(Input[])
    // Lets say the challanger maps keccak256(abi.encode(outputs)) => keccak256(OrderKey).
    // Then we can easily check if these outputs have all been matched.
    bytes outputs; // abi.encode(output[])
}


///////////////////
// Reactor types //
///////////////////

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
