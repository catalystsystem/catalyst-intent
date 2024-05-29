// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Collateral, ReactorInfo } from "../interfaces/Structs.sol";

struct LimitOrder {
    ReactorInfo reactorContext;
    
    uint96 nonce;

    // Order inputs
    uint256 inputAmount;
    address inputToken;

    // Collateral
    Collateral collateral;

    // Destination chain context
    address oracle;
    bytes32 destinationChainIdentifier;
    address remoteOracle;
    bytes32 destinationAsset; // TODO: Is this a waste? Can we use this better?
    bytes32 destinationAddress;
    uint256 amount;
}

/**
 * @notice Helper library for the Limit order type.
 * @dev Notice that when hashing limit order, we hash it as a large struct instead of a lot of smaller structs.
 */
library LimitOrderType {
    bytes constant LIMIT_ORDER_TYPE = abi.encodePacked(
        "LimitOrder(",
        // ReactorInfo
            "addres reactor",
            "uint40 fillByDeadline",
            "uint40 challangeDeadline",
            "uint40 proofDeadline",
        "uint96 nonce",
        // Order Inputs
            "uint256 inputAmount",
            "address inputToken",
        // Collateral
            "address collateralToken", // TODO: Just use gas?
            "uint256 fillerCollateralAmount",
            "uint256 challangerCollateralAmount",
        // Destination chain context
            "address oracle",
            "bytes32 destinationChainIdentifier",
            "address remoteOracle",
            "bytes32 destinationAsset",
            "bytes32 destinationAddress",
            "uint256 amount",
        ")"
    );
    bytes32 constant LIMIT_ORDER_TYPE_HASH = keccak256(LIMIT_ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";

    // TODO: Figure out permit2 types.
    string constant PERMIT2_WITNESS_TYPE = string(
        abi.encodePacked(
            "LimitOrder witness)",
            LIMIT_ORDER_TYPE,
            TOKEN_PERMISSIONS_TYPE
        )
    );

    function hash(LimitOrder calldata order) internal pure returns(bytes32) {
        return keccak256(abi.encode(
            LIMIT_ORDER_TYPE_HASH,
            // ReactorInfo
                order.reactorContext.reactor,
                order.reactorContext.fillByDeadline,
                order.reactorContext.challangeDeadline,
                order.reactorContext.proofDeadline,
            order.nonce,
            // Order Inputs
                order.inputAmount,
                order.inputToken,
            // Collateral
                order.collateral.collateralToken,
                order.collateral.fillerCollateralAmount,
                order.collateral.challangerCollateralAmount,
            // Destination chain context
                order.oracle,
                order.destinationChainIdentifier,
                order.remoteOracle,
                order.destinationAsset,
                order.destinationAddress,
                order.amount
            // etc...
        ));
    }

    function verify(LimitOrder calldata order, bytes calldata signature) internal pure returns(bytes32 orderHash, address signer) {
        orderHash = hash(order);
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(signature, (uint8, bytes32, bytes32));
        
        signer = ecrecover(orderHash, v, r, s);

        return (orderHash, signer);
    }
}
