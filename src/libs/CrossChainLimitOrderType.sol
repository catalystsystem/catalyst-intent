// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output } from "../interfaces/ISettlementContract.sol";
import { Collateral } from "../interfaces/Structs.sol";
import { CROSS_CHAIN_ORDER_TYPE_STUB, INPUT_TYPE_STUB, OUTPUT_TYPE_STUB } from "./CrossChainOrderLib.sol";

struct LimitOrderData {
    uint32 proofDeadline;
    address collateralToken;
    uint256 fillerCollateralAmount;
    uint256 challangerCollateralAmount; // TODO: use factor on fillerCollateralAmount
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
        "uint256 challangerCollateralAmount,",
        "address localOracle,",
        "bytes32 remoteOracle,",
        "Input input,",
        "Output output",
        ")",
        OUTPUT_TYPE_STUB,
        INPUT_TYPE_STUB
    );

    bytes32 constant LIMIT_ORDER_DATA_TYPE_HASH = keccak256(LIMIT_ORDER_DATA_TYPE);

    bytes constant CROSS_CHAIN_ORDER_TYPE = abi.encodePacked(
        CROSS_CHAIN_ORDER_TYPE_STUB,
        "LimitOrderData orderData)", // New order types need to replace this field.
        LIMIT_ORDER_DATA_TYPE
    );

    bytes32 internal constant CROSS_CHAIN_ORDER_TYPE_HASH = keccak256(CROSS_CHAIN_ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string constant PERMIT2_WITNESS_TYPE =
        string(abi.encodePacked("CrossChainOrder witness)", CROSS_CHAIN_ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    // TODO: include orderDataHash here?
    function hash(CrossChainOrder calldata order, bytes32 orderDataHash) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked( // TODO: bytes.concat
                CROSS_CHAIN_ORDER_TYPE_HASH,
                order.settlementContract,
                order.swapper,
                order.nonce,
                order.originChainId,
                order.initiateDeadline,
                order.fillDeadline,
                orderDataHash
            )
        );
    }

    function hashInput(Input memory input) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(INPUT_TYPE_STUB, input.token, input.amount));
    }

    function hashOutput(Output memory output) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(OUTPUT_TYPE_STUB, output.token, output.amount, output.recipient, output.chainId));
    }

    // TODO: Make a bytes calldata version of this functon.
    function hashOrderData(LimitOrderData memory orderData) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked( // todo: bytes.concat
                LIMIT_ORDER_DATA_TYPE_HASH,
                orderData.proofDeadline,
                orderData.collateralToken,
                orderData.fillerCollateralAmount,
                orderData.challangerCollateralAmount,
                orderData.localOracle,
                orderData.remoteOracle,
                hashInput(orderData.input),
                hashOutput(orderData.output)
            )
        );
    }

    function decodeOrderData(bytes calldata orderBytes) internal pure returns (LimitOrderData memory limitData) {
        return limitData = abi.decode(orderBytes, (LimitOrderData));
    }
}
