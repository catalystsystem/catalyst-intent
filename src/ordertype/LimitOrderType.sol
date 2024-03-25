// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Collateral, ReactorInfo } from "../interfaces/Structs.sol";

struct LimitOrder {
    ReactorInfo reactorContext;

    // Order inputs
    uint256 inputAmount;
    address inputToken;

    // Collateral
    Collateral collateral;

    // Destination chain context
    address oracle;
    bytes32 destinationChainIdentifier;
    bytes destinationAddress;
    uint256 amount;
}

/**
 * @notice Helper library for the Limit order type.
 * @dev Notice that when hashing limit order, we hash it as a large struct instead of a lot of smaller structs.
 */
library LimitOrderType {
    bytes constant LIMIT_ORDER_TYPE = abi.encodePacked(
        "LimitOrder(",
        "...",
        ")"
    );
    bytes32 constant LIMIT_ORDER_TYPE_HASH = keccak256(LIMIT_ORDER_TYPE);

    // TODO: Figure out permit2 types.
    string constant PERMIT2_WITNESS_TYPE = string(
        abi.encodePacked(
            "LimitOrder witness)",
            LIMIT_ORDER_TYPE
        )
    );

    function hash(LimitOrder memory order) internal pure returns(bytes32) {
        return keccak256(abi.encode(
            LIMIT_ORDER_TYPE_HASH,
            order.reactorContext.reactor,
            order.reactorContext.fillByDeadline,
            order.reactorContext.challangePeriod
            // etc...
        ));
    }
}
