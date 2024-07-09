// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output } from "../interfaces/ISettlementContract.sol";
import { CrossChainOrderType } from "./CrossChainOrderType.sol";

struct LimitMultipleOrdersData {
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

library CrossChainLimitMultipleOrdersType {
    bytes constant LIMIT_Multiple_ORDERS_DATA_TYPE = abi.encodePacked(
        "LimitOrderData(",
        "uint32 proofDeadline,",
        "uint32 challengeDeadline",
        "address collateralToken,",
        "uint256 fillerCollateralAmount,",
        "uint256 challengerCollateralAmount,",
        "address localOracle,",
        "bytes32 remoteOracle,",
        "Input[] inputs,",
        "Output[] outputs",
        ")",
        CrossChainOrderType.OUTPUT_TYPE_STUB,
        CrossChainOrderType.INPUT_TYPE_STUB
    );

    bytes32 constant LIMIT_MULTIPLE_ORDERS_DATA_TYPE_HASH = keccak256(LIMIT_Multiple_ORDERS_DATA_TYPE);

    function permit2WitnessType() internal pure returns (string memory permit2WitnessTypeString) {
        permit2WitnessTypeString = string(
            abi.encodePacked("CrossChainOrder witness)", _getOrderType(), CrossChainOrderType.TOKEN_PERMISSIONS_TYPE)
        );
    }

    function orderTypeHash() internal pure returns (bytes32) {
        return keccak256(_getOrderType());
    }

    function hashOrderDataM(LimitMultipleOrdersData memory orderData) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                LIMIT_MULTIPLE_ORDERS_DATA_TYPE_HASH,
                bytes4(orderData.proofDeadline),
                bytes4(orderData.challengeDeadline),
                bytes20(orderData.collateralToken),
                bytes32(orderData.fillerCollateralAmount),
                bytes32(orderData.challengerCollateralAmount),
                bytes20(orderData.localOracle),
                orderData.remoteOracle,
                CrossChainOrderType.hashInputs(orderData.inputs),
                CrossChainOrderType.hashOutputs(orderData.outputs)
            )
        );
    }

    function hashOrderData(LimitMultipleOrdersData calldata orderData) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                LIMIT_MULTIPLE_ORDERS_DATA_TYPE_HASH,
                bytes4(orderData.proofDeadline),
                bytes4(orderData.challengeDeadline),
                bytes20(orderData.collateralToken),
                bytes32(orderData.fillerCollateralAmount),
                bytes32(orderData.challengerCollateralAmount),
                bytes20(orderData.localOracle),
                orderData.remoteOracle,
                CrossChainOrderType.hashInputs(orderData.inputs),
                CrossChainOrderType.hashOutputs(orderData.outputs)
            )
        );
    }

    function decodeOrderData(bytes calldata orderBytes)
        internal
        pure
        returns (LimitMultipleOrdersData memory limitData)
    {
        return limitData = abi.decode(orderBytes, (LimitMultipleOrdersData));
    }

    function _getOrderType() private pure returns (bytes memory) {
        return CrossChainOrderType.crossOrderType("LimitMultipleOrdersData orderData", LIMIT_Multiple_ORDERS_DATA_TYPE);
    }
}
