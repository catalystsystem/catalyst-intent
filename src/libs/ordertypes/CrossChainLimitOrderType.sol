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
        "Input[] inputs,",
        "OutputDescription[] outputs",
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
        "Input[] inputs,",
        "OutputDescription[] outputs",
        ")"
    );

    bytes constant CROSS_LIMIT_ORDER_TYPE_STUP = abi.encodePacked(
        "CrossChainOrder(",
        "address settlementContract,",
        "address swapper,",
        "uint256 nonce,",
        "uint32 originChainId,",
        "uint32 initiateDeadline,",
        "uint32 fillDeadline,",
        "CatalystLimitOrderData orderData",
        ")"
    );

    bytes32 constant LIMIT_ORDER_DATA_TYPE_HASH = keccak256(LIMIT_ORDER_DATA_TYPE);

    function decodeOrderData(bytes calldata orderBytes) internal pure returns (LimitOrderData memory limitData) {
        return limitData = abi.decode(orderBytes, (LimitOrderData));
    }

    function hashOrderDataM(LimitOrderData memory orderData) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                LIMIT_ORDER_DATA_TYPE_HASH,
                bytes32(uint256(orderData.proofDeadline)),
                bytes32(uint256(orderData.challengeDeadline)),
                bytes32(uint256(uint160(orderData.collateralToken))),
                bytes32(orderData.fillerCollateralAmount),
                bytes32(orderData.challengerCollateralAmount),
                bytes32(uint256(uint160(orderData.localOracle))),
                CrossChainOrderType.hashInputs(orderData.inputs),
                CrossChainOrderType.hashOutputs(orderData.outputs)
            )
        );
    }

    function hashOrderData(LimitOrderData calldata orderData) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                LIMIT_ORDER_DATA_TYPE_HASH,
                bytes32(uint256(orderData.proofDeadline)),
                bytes32(uint256(orderData.challengeDeadline)),
                bytes32(uint256(uint160(orderData.collateralToken))),
                bytes32(orderData.fillerCollateralAmount),
                bytes32(orderData.challengerCollateralAmount),
                bytes32(uint256(uint160(orderData.localOracle))),
                CrossChainOrderType.hashInputs(orderData.inputs),
                CrossChainOrderType.hashOutputs(orderData.outputs)
            )
        );
    }

    function crossOrderHash(CrossChainOrder calldata order) internal pure returns (bytes32) {
        LimitOrderData memory limitOrderData = decodeOrderData(order.orderData);
        return keccak256(
            abi.encode(
                keccak256(abi.encodePacked(CROSS_LIMIT_ORDER_TYPE_STUP, LIMIT_ORDER_DATA_TYPE)),
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
                CROSS_LIMIT_ORDER_TYPE_STUP,
                CrossChainOrderType.INPUT_TYPE_STUB,
                CrossChainOrderType.OUTPUT_TYPE_STUB,
                CrossChainOrderType.TOKEN_PERMISSIONS_TYPE
            )
        );
    }
}
