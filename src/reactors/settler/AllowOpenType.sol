// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/** @notice Signed struct */
struct AllowOpen {
    bytes32 orderId;
    address originSettler;
    address destination;
    bytes call;
}

/**
 * @notice Helper library for the Allow Open type.
 * TYPE_PARTIAL: An incomplete type. Is missing a field.
 * TYPE_STUB: Type has no subtypes. 
 * TYPE: Is complete including sub-types.
 */
library AllowOpenType {

    bytes constant ALLOW_OPEN_TYPE_STUB = abi.encodePacked(
        "AllowOpen("
        "bytes32 orderId,"
        "address originSettler,"
        "address destination,"
        "bytes call"
        ")"
    );

    bytes32 constant ALLOW_OPEN_TYPE_HASH = keccak256(ALLOW_OPEN_TYPE_STUB);

    function hashAllowOpen(
        bytes32 orderId,
        address originSettler,
        address destination,
        bytes calldata call
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ALLOW_OPEN_TYPE_HASH,
                orderId,
                originSettler,
                destination,
                keccak256(call)
            )
        );
    }
}
