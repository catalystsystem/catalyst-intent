// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "./CatalystOrderType.sol";

library OutputEncodingLibrary {
    error RemoteCallOutOfRange();
    error fulfillmentContextCallOutOfRange();

    // --- Hashing Encoding --- //

    function _encodeOutput(
        bytes32 solver,
        uint40 timestamp,
        bytes32 orderId,
        bytes32 token,
        uint256 amount,
        bytes32 recipient,
        bytes memory remoteCall,
        bytes memory fulfillmentContext
    ) internal pure returns (bytes memory encodedOutput) {
        // Check that the length of remoteCall & fulfillmentContext does not exceed type(uint16).max
        if (remoteCall.length > type(uint16).max) revert RemoteCallOutOfRange();
        if (fulfillmentContext.length > type(uint16).max) revert fulfillmentContextCallOutOfRange();

        return encodedOutput = abi.encodePacked(
            solver,
            timestamp,
            orderId,
            token,
            amount,
            recipient,
            uint16(remoteCall.length), // To protect against data collisions
            remoteCall,
            uint16(fulfillmentContext.length), // To protect against data collisions
            fulfillmentContext
        );
    }

    // Predictable encoding of outputDescription that overlaps with the message encoding
    function encodeEntireOutput(
        OutputDescription memory outputDescription
    ) internal pure returns (bytes memory encodedOutput) {
        bytes memory remoteCall = outputDescription.remoteCall;
        bytes memory fulfillmentContext = outputDescription.fulfillmentContext;
        // Check that the length of remoteCall & fulfillmentContext does not exceed type(uint16).max
        if (remoteCall.length > type(uint16).max) revert RemoteCallOutOfRange();
        if (fulfillmentContext.length > type(uint16).max) revert fulfillmentContextCallOutOfRange();

        return encodedOutput = abi.encodePacked(
            outputDescription.remoteOracle,
            outputDescription.chainId,
            outputDescription.token,
            outputDescription.amount,
            outputDescription.recipient,
            uint16(remoteCall.length), // To protect against data collisions
            remoteCall,
            uint16(fulfillmentContext.length), // To protect against data collisions
            fulfillmentContext
        );
    }

    function outputHash(OutputDescription calldata output) pure internal returns(bytes32) {
        // Notice this is not a perfect hash of the OutputDescription. It is missing chainId.
        return keccak256(encodeEntireOutput(output));
    }

    function payloadToOutputHash(
        bytes32 remoteOracle,
        uint256 chainId,
        bytes calldata remainingPayload
    ) pure internal returns (bytes32) {
        return keccak256(abi.encodePacked(
            remoteOracle,
            chainId,
            remainingPayload
        ));
    }

    function encodeOutputDescriptionIntoPayload(
        bytes32 solver,
        uint40 timestamp,
        bytes32 orderId,
        OutputDescription memory outputDescription
    ) internal pure returns (bytes memory encodedOutput) {
        return encodedOutput = _encodeOutput(
            solver,
            timestamp,
            orderId,
            outputDescription.token,
            outputDescription.amount,
            outputDescription.recipient,
            outputDescription.remoteCall,
            outputDescription.fulfillmentContext
        );
    }

    function decodePayloadSolver(
        bytes calldata payload
    ) internal pure returns (bytes32 solver) {
        return solver = bytes32(payload[0:32]);
    }

    function decodePayloadTimestamp(
        bytes calldata payload
    ) internal pure returns (uint40 timestamp) {
        return timestamp = uint40(bytes5(payload[32:37]));
    }

    function decodePayloadOrderId(
        bytes calldata payload
    ) internal pure returns (bytes32 orderId) {
        return orderId = bytes32(payload[37:69]);
    }

    function selectRemainingPayload(
        bytes calldata payload
    ) internal pure returns (bytes calldata remainingPayload) {
        return remainingPayload = payload[69:];
    }
}
