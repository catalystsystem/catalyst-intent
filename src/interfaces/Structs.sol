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
 * - Claimed: A solver has claimed this order. Progresses to Challenged or OPFilled.
 * - Challenged: A claimed order was challenged. Progresses to Fraud or Proven.
 * - Fraud: The solver did not prove delivery & Challenger claiemd the collateral. Final.
 * - OPFilled: A claimed order was not challenged. Paid inputs to solver. Final.
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
// @param initTimestamp is for blocking previous fillings.

struct OrderContext {
    OrderStatus status;
    address challenger;
    address fillerAddress;
    uint32 orderPurchaseDeadline;
    uint16 orderDiscount;
    uint32 initTimestamp; // TODO: move to orderkey.
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
    address swapper; // TODO: Include filler in this order?
    uint96 nonce;
    // Collateral
    Collateral collateral;
    uint32 originChainId;
    // Proof Context
    address localOracle; // The oracle that can satisfy a dispute.
    bytes32 remoteOracle; // Remote oracle. If address(0), is local.
    bytes32 oracleProofHash; // TODO: figure out the best way to store proof details. Is the below enough?
    // TODO: Figure out how to do remote calls (gas limit + fallback + calldata)
    Input[] inputs;
    // Lets say the challenger maps keccak256(abi.encode(outputs)) => keccak256(OrderKey).
    // Then we can easily check if these outputs have all been matched.
    Output[] outputs;
}

struct ReactorInfo {
    // The contract that is managing this order.
    address reactor;
    // Order resolution times
    uint32 fillByDeadline;
    uint32 challengeDeadline;
    uint32 proofDeadline;
}

struct Collateral {
    address collateralToken; // TODO: Just use gas?
    uint256 fillerCollateralAmount;
    uint256 challengerCollateralAmount;
}
