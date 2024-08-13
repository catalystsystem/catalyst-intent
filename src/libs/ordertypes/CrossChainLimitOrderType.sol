// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output } from "../../interfaces/ISettlementContract.sol";
import { CrossChainOrderType } from "./CrossChainOrderType.sol";

struct LimitOrderData {
    uint32 proofDeadline;
    uint32 challengeDeadline;
    address collateralToken;
    uint256 fillerCollateralAmount;
    uint256 challengerCollateralAmount; // TODO: use factor on fillerCollateralAmount
    address localOracle;
    bytes32 remoteOracle; // TODO: figure out how to trustless.
    Input[] inputs;
    Output[] outputs;
}

/**
 * @notice Helper library for the Limit order type.
 * @dev Notice that when hashing limit order, we hash it as a large struct instead of a lot of smaller structs.
 */
library CrossChainLimitOrderType {
    bytes constant LIMIT_ORDER_DATA_TYPE = abi.encodePacked(
        "CatalystLimitOrderData(",
        "uint32 proofDeadline,",
        "uint32 challengeDeadline,",
        "address collateralToken,",
        "uint256 fillerCollateralAmount,",
        "uint256 challengerCollateralAmount,",
        "address localOracle,",
        "bytes32 remoteOracle,",
        "Input[] inputs,",
        "Output[] outputs",
        ")",
        CrossChainOrderType.INPUT_TYPE_STUB,
        CrossChainOrderType.OUTPUT_TYPE_STUB
    );

    bytes constant LIMIT_ORDER_DATA_TYPE_ONLY = abi.encodePacked(
        "CatalystLimitOrderData(",
        "uint32 proofDeadline,",
        "uint32 challengeDeadline,",
        "address collateralToken,",
        "uint256 fillerCollateralAmount,",
        "uint256 challengerCollateralAmount,",
        "address localOracle,",
        "bytes32 remoteOracle,",
        "Input[] inputs,",
        "Output[] outputs",
        ")"
    );

    bytes32 constant LIMIT_ORDER_DATA_TYPE_HASH = keccak256(LIMIT_ORDER_DATA_TYPE);

    function orderTypeHash() internal pure returns (bytes32) {
        return keccak256(getOrderType());
    }

    function hashOrderDataM(LimitOrderData memory orderData) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                LIMIT_ORDER_DATA_TYPE_HASH,
                orderData.proofDeadline,
                orderData.challengeDeadline,
                orderData.collateralToken,
                orderData.fillerCollateralAmount,
                orderData.challengerCollateralAmount,
                orderData.localOracle,
                orderData.remoteOracle,
                CrossChainOrderType.hashInputs(orderData.inputs),
                CrossChainOrderType.hashOutputs(orderData.outputs)
            )
        );
    }

    function hashOrderData(LimitOrderData calldata orderData) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                LIMIT_ORDER_DATA_TYPE_HASH,
                orderData.proofDeadline,
                orderData.challengeDeadline,
                orderData.collateralToken,
                orderData.fillerCollateralAmount,
                orderData.challengerCollateralAmount,
                orderData.localOracle,
                orderData.remoteOracle,
                CrossChainOrderType.hashInputs(orderData.inputs),
                CrossChainOrderType.hashOutputs(orderData.outputs)
            )
        );
    }

    function decodeOrderData(bytes calldata orderBytes) internal pure returns (LimitOrderData memory limitData) {
        return limitData = abi.decode(orderBytes, (LimitOrderData));
    }

    function getOrderType() internal pure returns (bytes memory) {
        return CrossChainOrderType.crossOrderType("CatalystLimitOrderData orderData", LIMIT_ORDER_DATA_TYPE_ONLY);
    }
}
