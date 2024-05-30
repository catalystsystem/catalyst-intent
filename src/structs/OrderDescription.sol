// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/// @notice The order description.
struct OrderDescription {
    // The address to evaluate the order. Also determines the type of the order.
    address orderType;
    // The account on the destination chain.
    // Encoding depends on the implementation, evm is abi.encodePacked().
    bytes destinationAccount;
    // Timestamp for when the order is invalid. // TODO: Should also be used to nonce the order?
    uint64 baseTimeout;
    // TODO: Include swapper address?
    // For: It would make all swap hashes unique.
    // Against: Not really needed since the recipitent should be the unique-ish. We can get the user from the signature.
    // address user;
    // Custom execution logic. Only on source chain.
    address postExecutionHook;
    // Payload for the hook.
    bytes postExecutionHookData;
}

library OrderDescriptionHash {
    // Define the order description such that we can hash it.
    bytes constant ORDER_DESCRIPTION_TYPE =
        "OrderDescription(address orderType,bytes destinationAccount,uint64 baseTimeout,address postExecutionHook,bytes postExecutionHookData)";

    // The hash of the order description struct identifier
    bytes32 constant ORDER_DESCRIPTION_TYPE_HASH = keccak256(ORDER_DESCRIPTION_TYPE);

    /// @notice Get the hash of the order description
    function hash(OrderDescription memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_DESCRIPTION_TYPE_HASH,
                order.orderType,
                keccak256(order.destinationAccount),
                order.baseTimeout,
                order.postExecutionHook,
                keccak256(order.postExecutionHookData)
            )
        );
    }
}
