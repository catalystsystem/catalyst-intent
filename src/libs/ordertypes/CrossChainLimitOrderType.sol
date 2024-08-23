// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CrossChainOrder, Input } from "../../interfaces/ISettlementContract.sol";

import { OutputDescription } from "../../interfaces/Structs.sol";

import { CrossChainOrderType } from "./CrossChainOrderType.sol";

struct LimitOrderData {
    uint32 proofDeadline;
    uint32 challengeDeadline;
    address collateralToken;
    uint256 fillerCollateralAmount;
    uint256 challengerCollateralAmount;
    address localOracle;
    Input[] inputs;
    OutputDescription[] outputs;
}

/**
 * @notice Helper library for the Limit order type.
 */
library CrossChainLimitOrderType {
    bytes constant LIMIT_ORDER_DATA_TYPE = abi.encodePacked(
        LIMIT_ORDER_DATA_TYPE_ONLY, CrossChainOrderType.INPUT_TYPE_STUB, CrossChainOrderType.OUTPUT_TYPE_STUB
    );

    bytes constant LIMIT_ORDER_DATA_TYPE_ONLY = abi.encodePacked(
        "CatalystLimitOrderData(",
        "uint32 proofDeadline,",
        "uint32 challengeDeadline,",
        "address collateralToken,",
        "uint256 fillerCollateralAmount,",
        "uint256 challengerCollateralAmount,",
        "address localOracle,",
        "Input[] inputs,",
        "OutputDescription[] outputs",
        ")"
    );

    bytes constant CROSS_LIMIT_ORDER_TYPE_STUB = abi.encodePacked(
        CrossChainOrderType.CROSS_CHAIN_ORDER_TYPE_NO_DATA_STUB, "CatalystLimitOrderData orderData", ")"
    );

    bytes32 constant LIMIT_ORDER_DATA_TYPE_HASH = keccak256(LIMIT_ORDER_DATA_TYPE);

    function decodeOrderData(bytes calldata orderBytes) internal pure returns (LimitOrderData memory limitData) {
        return limitData = abi.decode(orderBytes, (LimitOrderData));
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
                CrossChainOrderType.hashInputs(orderData.inputs),
                CrossChainOrderType.hashOutputs(orderData.outputs)
            )
        );
    }

    function crossOrderHash(CrossChainOrder calldata order) internal pure returns (bytes32) {
        LimitOrderData memory limitOrderData = decodeOrderData(order.orderData);
        return keccak256(
            abi.encode(
                keccak256(abi.encodePacked(CROSS_LIMIT_ORDER_TYPE_STUB, LIMIT_ORDER_DATA_TYPE)),
                order.settlementContract,
                order.swapper,
                order.nonce,
                order.originChainId,
                order.initiateDeadline,
                order.fillDeadline,
                hashOrderDataM(limitOrderData)
            )
        );
    }

    function permit2WitnessType() internal pure returns (string memory permit2WitnessTypeString) {
        permit2WitnessTypeString = string(
            abi.encodePacked(
                "CrossChainOrder witness)",
                LIMIT_ORDER_DATA_TYPE_ONLY,
                CROSS_LIMIT_ORDER_TYPE_STUB,
                CrossChainOrderType.INPUT_TYPE_STUB,
                CrossChainOrderType.OUTPUT_TYPE_STUB,
                CrossChainOrderType.TOKEN_PERMISSIONS_TYPE
            )
        );
    }
}
