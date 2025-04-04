// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/**
 * @notice Signed struct
 */
struct OrderPurchase {
    bytes32 orderId;
    address originSettler;
    address destination;
    bytes call;
    uint64 discount;
    uint32 timeToBuy;
}

/**
 * @notice Helper library for the Order Purchase type.
 * TYPE_PARTIAL: An incomplete type. Is missing a field.
 * TYPE_STUB: Type has no subtypes.
 * TYPE: Is complete including sub-types.
 */
library OrderPurchaseType {
    bytes constant ORDER_PURCHASE_TYPE_STUB = abi.encodePacked("OrderPurchase(" "bytes32 orderId," "address originSettler," "address destination," "bytes call," "uint64 discount," "uint32 timeToBuy" ")");

    bytes32 constant ORDER_PURCHASE_TYPE_HASH = keccak256(ORDER_PURCHASE_TYPE_STUB);

    function hashOrderPurchase(bytes32 orderId, address originSettler, address destination, bytes calldata call, uint64 discount, uint32 timeToBuy) internal pure returns (bytes32) {
        return keccak256(abi.encode(ORDER_PURCHASE_TYPE_HASH, orderId, originSettler, destination, keccak256(call), discount, timeToBuy));
    }
}
