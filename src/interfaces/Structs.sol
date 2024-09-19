// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Input } from "./ISettlementContract.sol";

//////////////////
// Order types ///
//////////////////

/**
 * @notice The progressive order status of cross-chain orders:
 * - Unfilled: Default state. Progresses to Claimed.
 * - Claimed: A solver has claimed this order. Progresses to Challenged or OptimiscallyFilled.
 * - Challenged: A claimed order was challenged. Progresses to Fraud or Proven.
 * - Fraud: The solver did not prove delivery & Challenger claiemd the collateral. Final.
 * - OptimiscallyFilled: A claimed order was not challenged. Paid inputs to solver. Final.
 * - Proven: A solver proved settlement. Paid inputs to solver. Final.
 */
enum OrderStatus {
    Unfilled,
    Claimed,
    Challenged,
    Fraud,
    OptimiscallyFilled,
    Proven
}

/**
 * @notice Storage Slot used for initiated orders.
 * @param status Description of the status. Is OrderStatus Enum.
 * @param fillerAddress Address of the filler (Address that will get the inputs after successful order).
 * @param orderPurchaseDeadline If configured, an initiated order can be purchased until this deadline.
 * @param orderPurchaseDiscount The discount that an order gets by being purchased. Is of type(uint16).max.
 * @param challenger If the order has been challenged, is the address of challenger otherwise address(0).
 * @param identifier A hash used to configure the input payment with extra logic.
 */
struct OrderContext {
    OrderStatus status;
    address fillerAddress;
    uint32 orderPurchaseDeadline;
    uint16 orderPurchaseDiscount;
    address challenger;
    bytes32 identifier;
}

struct OutputDescription {
    /// @dev Contract on the destination that tells whether an order was filled.
    /// Format is bytes32() slice of the encoded bytearray from the messaging protocol (or bytes32(0) if local)
    bytes32 remoteOracle;
    /// @dev The address of the ERC20 token on the destination chain
    /// @dev address(0) used as a sentinel for the native token
    bytes32 token;
    /// @dev The amount of the token to be sent
    uint256 amount;
    /// @dev The address to receive the output tokens
    bytes32 recipient;
    /// @dev The destination chain for this output
    uint32 chainId;
    bytes remoteCall;
}

/**
 * @notice This is the simplified order after it has been validated and evaluated.
 * @dev Is used to keep the order context in calldata to save gas. The hash of the orderKey
 * is used to identify orders.
 * - Validated: We check that the signature of the order matches the relevant order.
 * - Evaluated: The order has been evaluated for its respective inputs and outputs
 */
struct OrderKey {
    // The contract that is managing this order.
    ReactorInfo reactorContext;
    // Who this order was claimed by.
    address swapper;
    // Nonce is unused in code but is used to make orderKeyHashes unique
    // between orders. Since a nonce can only be used once, this makes an effective
    // order differentiator.
    uint96 nonce;
    // Collateral
    Collateral collateral;
    uint32 originChainId;
    // Proof Context
    address localOracle; // The oracle that can satisfy a dispute.
    Input[] inputs;
    // Lets say the challenger maps keccak256(abi.encode(outputs)) => keccak256(OrderKey).
    // Then we can easily check if these outputs have all been matched.
    OutputDescription[] outputs;
}

struct ReactorInfo {
    // The contract that is managing this order.
    address reactor;
    // Order resolution times
    uint32 fillDeadline;
    uint32 challengeDeadline;
    uint32 proofDeadline;
}

struct Collateral {
    address collateralToken;
    uint256 fillerCollateralAmount;
    uint256 challengerCollateralAmount;
}
