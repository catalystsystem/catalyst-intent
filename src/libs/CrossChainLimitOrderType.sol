// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output } from "../interfaces/ISettlementContract.sol";
import { CrossChainOrderType } from "./CrossChainOrderType.sol";

struct LimitOrderData {
    uint32 proofDeadline;
    address collateralToken;
    uint256 fillerCollateralAmount;
    uint256 challengerCollateralAmount; // TODO: use factor on fillerCollateralAmount
    address localOracle;
    bytes32 remoteOracle; // TODO: figure out how to trustless.
    Input input;
    Output output;
}

/**
 * @notice Helper library for the Limit order type.
 * @dev Notice that when hashing limit order, we hash it as a large struct instead of a lot of smaller structs.
 */
library CrossChainLimitOrderType {
    bytes constant LIMIT_ORDER_DATA_TYPE = abi.encodePacked(
        "LimitOrderData(",
        "uint32 proofDeadline,",
        "address collateralToken,",
        "uint256 fillerCollateralAmount,",
        "uint256 challengerCollateralAmount,",
        "address localOracle,",
        "bytes32 remoteOracle,",
        "Input input,",
        "Output output",
        ")",
        CrossChainOrderType.OUTPUT_TYPE_STUB,
        CrossChainOrderType.INPUT_TYPE_STUB
    );

    bytes32 constant LIMIT_ORDER_DATA_TYPE_HASH = keccak256(LIMIT_ORDER_DATA_TYPE);

    function permit2WitnessType() internal pure returns (string memory permit2WitnessTypeString) {
        permit2WitnessTypeString = string(
            abi.encodePacked("CrossChainOrder witness)", _getOrderType(), CrossChainOrderType.TOKEN_PERMISSIONS_TYPE)
        );
    }

    function orderTypeHash() internal pure returns (bytes32) {
        return keccak256(_getOrderType());
    }

    // TODO: Make a bytes calldata version of this function.
    function hashOrderData(LimitOrderData memory orderData) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked( // todo: bytes.concat
                LIMIT_ORDER_DATA_TYPE_HASH,
                orderData.proofDeadline,
                orderData.collateralToken,
                orderData.fillerCollateralAmount,
                orderData.challengerCollateralAmount,
                orderData.localOracle,
                orderData.remoteOracle,
                CrossChainOrderType.hashInput(orderData.input),
                CrossChainOrderType.hashOutput(orderData.output)
            )
        );
    }

    function decodeOrderData(bytes calldata orderBytes) internal pure returns (LimitOrderData memory limitData) {
        return limitData = abi.decode(orderBytes, (LimitOrderData));
    }

    function _getOrderType() private pure returns (bytes memory) {
        return CrossChainOrderType.crossOrderType("LimitOrderData orderData", LIMIT_ORDER_DATA_TYPE);
    }
}
