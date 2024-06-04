// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Collateral } from "../interfaces/Structs.sol";
import { CROSS_CHAIN_ORDER_TYPE } from "./CrossChainOrderLib.sol";

// TODO: struct def.
struct CrossChainLimitOrder {
    // CrossChainOrder
    address settlementContract;
    address swapper;
    uint256 nonce;
    uint32 originChainId;
    uint32 initiateDeadline;
    uint32 fillDeadline;
    bytes orderData;

    // Limit Data
    uint32 proofDeadline;

    address collateralToken;
    uint256 fillerCollateralAmount;
    uint256 challangerCollateralAmount; // TODO: use factor on fillerCollateralAmount

    address localOracle;
    bytes32 remoteOracle;
    bytes32 destinationChainId;

    bytes32 destinationAsset; // TODO: Is this a waste? Can we use this better?
    bytes32 destinationAddress; // TODO bytes? For better future compatability?
    uint256 amount;
}

struct LimitData {

    uint32 proofDeadline;

    address collateralToken;
    uint256 fillerCollateralAmount;
    uint256 challangerCollateralAmount; // TODO: use factor on fillerCollateralAmount

    address localOracle;
    bytes32 remoteOracle;
    bytes32 destinationChainId;

    bytes32 destinationAsset; // TODO: Is this a waste? Can we use this better?
    bytes32 destinationAddress; // TODO bytes? For better future compatability?
    uint256 amount;
}

/**
 * @notice Helper library for the Limit order type.
 * @dev Notice that when hashing limit order, we hash it as a large struct instead of a lot of smaller structs.
 */
library CrossChainLimitOrderType {
    bytes constant LIMIT_ORDER_TYPE = abi.encodePacked(
        "CrossChainLimitOrder(",
            CROSS_CHAIN_ORDER_TYPE,
            "uint32 proofDeadline",
            "address collateralToken",
            "uint256 fillerCollateralAmount",
            "uint256 challangerCollateralAmount",
            "address localOracle",
            "bytes32 remoteOracle",
            "bytes32 destinationChainId",
            "bytes32 destinationAsset",
            "bytes32 destinationAddress",
            "uint256 amount"
    );
    bytes32 constant LIMIT_ORDER_TYPE_HASH = keccak256(LIMIT_ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";

    // TODO: Figure out permit2 types.
    string constant PERMIT2_WITNESS_TYPE =
        string(abi.encodePacked("CrossChainLimitOrder witness)", LIMIT_ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    function hash(CrossChainLimitOrder calldata order) internal pure returns (bytes32) {
        return keccak256(hex""
            /* abi.encode(
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
            ) */
        )
        // etc...
        ;
    }

    function decodeOrderData(bytes calldata orderBytes) internal pure returns(LimitData memory limitData) {
        return limitData = abi.decode(orderBytes, (LimitData));
    }
}
