// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "../reactors/CatalystOrderType.sol";

/**
 * @notice Converts Catalyst OutputDescriptions to and from byte payloads.
 * @dev The library defines 2 payload structures, one for internal usage and one for cross-chain communication.
 * - outputHash is a hash of an outputDescription. This uses a compact and unique encoding scheme.
 * Its purpose is to prove a way to reconstruct payloads AND block dublicate fills.
 * - payload is a description of what was filled on a remote chain. Its purpose is to provide a
 * source of truth.
 *
 * The structure of both are 
 *
 *  Output Hash (Used for fill management on remote EVM chains)
 *      REMOTE_ORACLE                   0               (32 bytes)
 *      + CHAIN_ID                      32              (32 bytes)
 *
 *  Payload (Used as a portable format that can prove what happened on the remote chain)
 *      SOLVER                          0               (32 bytes)
 *      + TIMESTAMP                     32              (5 bytes)
 *      + ORDERID                       37              (32 bytes)
 *
 * Common Payload. Is identical between the both encoding scheme
 *      + TOKEN                         Y               (32 bytes)
 *      + AMOUNT                        Y+32            (32 bytes)
 *      + RECIPIENT                     Y+64            (32 bytes)
 *      + REMOTE_CALL_LENGTH            Y+96            (2 bytes)
 *      + REMOTE_CALL                   Y+98            (LENGTH bytes)
 *      + FULFILLMENT_CONTEXT_LENGTH    Y+98+RC_LENGTH  (2 bytes)
 *      + FULFILLMENT_CONTEXT           Y+100+RC_LENGTH (LENGTH bytes)
 *
 * where Y is the offset from the specific encoding (either 64 or 69)
 *
 */
library OutputEncodingLib {
    error RemoteCallOutOfRange();
    error fulfillmentContextCallOutOfRange();

    // --- OutputDescription Encoding --- //

    function outputHash(OutputDescription calldata output) pure internal returns(bytes32) {
        return keccak256(encodeEntireOutput(output));
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

    // --- Payload Encoding --- //

    function encodeOutputDescriptionIntoPayload(
        bytes32 solver,
        uint40 timestamp,
        bytes32 orderId,
        OutputDescription memory outputDescription
    ) internal pure returns (bytes memory encodedOutput) {
        return encodedOutput = encodeOutput(
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

    function encodeOutput(
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

    // -- Payload Decoding Helpers -- //

    function decodePayloadSolver(
        bytes calldata payload
    ) internal pure returns (bytes32 solver) {
        assembly ("memory-safe") {
            // solver = bytes32(payload[0:32]);
            solver := calldataload(payload.offset)
        }
    }

    function decodePayloadTimestamp(
        bytes calldata payload
    ) internal pure returns (uint40 timestamp) {
        return timestamp = uint40(bytes5(payload[32:37]));
    }

    function decodePayloadOrderId(
        bytes calldata payload
    ) internal pure returns (bytes32 orderId) {
        assembly ("memory-safe") {
            // orderId = bytes32(payload[37:69]);
            orderId := calldataload(add(payload.offset, 37))
        }
    }

    function selectRemainingPayload(
        bytes calldata payload
    ) internal pure returns (bytes calldata remainingPayload) {
        return remainingPayload = payload[69:];
    }
}
