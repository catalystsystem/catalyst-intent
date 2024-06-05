// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Collateral } from "../interfaces/Structs.sol";
import { CrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { CROSS_CHAIN_ORDER_TYPE_STUB } from "./CrossChainOrderLib.sol";

struct LimitOrderData {
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
    bytes constant LIMIT_ORDER_DATA_TYPE = abi.encodePacked(
        "LimitOrderData(",
        "uint32 proofDeadline,",
        "address collateralToken,",
        "uint256 fillerCollateralAmount,",
        "uint256 challangerCollateralAmount,",
        "address localOracle,",
        "bytes32 remoteOracle,",
        "bytes32 destinationChainId,",
        "bytes32 destinationAsset,",
        "bytes32 destinationAddress,",
        "uint256 amount",
        ")"
    );

    bytes32 constant LIMIT_ORDER_DATA_TYPE_HASH = keccak256(LIMIT_ORDER_DATA_TYPE);

    bytes constant CROSS_CHAIN_ORDER_TYPE = abi.encodePacked(
        CROSS_CHAIN_ORDER_TYPE_STUB,
        "LimitOrderData orderData)", // New order types need to replace this field.
        LIMIT_ORDER_DATA_TYPE_HASH
    );

    bytes32 internal constant CROSS_CHAIN_ORDER_TYPE_HASH = keccak256(CROSS_CHAIN_ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string constant PERMIT2_WITNESS_TYPE =
        string(abi.encodePacked("CrossChainOrder witness)", CROSS_CHAIN_ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

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

    function hashOrderData(LimitOrderData memory orderData) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked( // todo: bytes.concat
                LIMIT_ORDER_DATA_TYPE,
                orderData.proofDeadline,
                orderData.collateralToken,
                orderData.fillerCollateralAmount,
                orderData.challangerCollateralAmount,
                orderData.localOracle,
                orderData.remoteOracle,
                orderData.destinationChainId,
                orderData.destinationAsset,
                orderData.destinationAddress,
                orderData.amount
            )
        );
    }

    function decodeOrderData(bytes calldata orderBytes) internal pure returns (LimitOrderData memory limitData) {
        return limitData = abi.decode(orderBytes, (LimitOrderData));
    }
}
