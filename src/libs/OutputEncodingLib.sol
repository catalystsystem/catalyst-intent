// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "../reactors/CatalystOrderType.sol";

/**
 * @notice Converts Catalyst OutputDescriptions to and from byte payloads.
 * @dev The library defines 2 payload encodings, one for internal usage and one for cross-chain communication.
 * - OutputDescription encoding describes a desired fill on a remote chain (encodes the fields of
 * an OutputDescription struct). This encoding is used to obtain collision free hashes that
 * uniquely identify OutputDescriptions.
 * - FillDescription encoding is used to describe what was filled on a remote chain. Its purpose is
 * to provide a source of truth.
 *
 * The structure of both are
 *
 * Encoded OutputDescription
 *      REMOTE_ORACLE                   0               (32 bytes)
 *      + CHAIN_ID                      32              (32 bytes)
 *      + COMMON_PAYLOAD                64
 *
 * Encoded FillDescription
 *      SOLVER                          0               (32 bytes)
 *      + ORDERID                       32              (32 bytes)
 *      + TIMESTAMP                     64              (4 bytes)
 *      + COMMON_PAYLOAD                68
 *
 * Common Payload. Is identical between both encoding scheme
 *      + TOKEN                         Y               (32 bytes)
 *      + AMOUNT                        Y+32            (32 bytes)
 *      + RECIPIENT                     Y+64            (32 bytes)
 *      + REMOTE_CALL_LENGTH            Y+96            (2 bytes)
 *      + REMOTE_CALL                   Y+98            (LENGTH bytes)
 *      + FULFILLMENT_CONTEXT_LENGTH    Y+98+RC_LENGTH  (2 bytes)
 *      + FULFILLMENT_CONTEXT           Y+100+RC_LENGTH (LENGTH bytes)
 *
 * where Y is the offset from the specific encoding (either 64 or 68)
 *
 */
library OutputEncodingLib {
    error FulfillmentContextCallOutOfRange();
    error RemoteCallOutOfRange();

    // --- OutputDescription Encoding --- //

    /**
     * @notice Predictable encoding of OutputDescription that deliberately overlaps with the payload encoding.
     * @dev This function uses length identifiers 2 bytes long. As a result, neither remoteCall nor fulfillmentContext
     * can be larger than 65535.
     */
    function encodeOutputDescription(
        OutputDescription calldata outputDescription
    ) internal pure returns (bytes memory encodedOutput) {
        bytes calldata remoteCall = outputDescription.remoteCall;
        bytes calldata fulfillmentContext = outputDescription.fulfillmentContext;
        // Check that the length of remoteCall & fulfillmentContext does not exceed type(uint16).max
        if (remoteCall.length > type(uint16).max) revert RemoteCallOutOfRange();
        if (fulfillmentContext.length > type(uint16).max) revert FulfillmentContextCallOutOfRange();

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

    /**
     * @notice Creates a unique hash of an OutputDescription
     * @dev This does provide a description of how an output was filled but just
     * an exact unique identifier for an output description. This identifier is
     * purely intended for the remote chain.
     */
    function getOutputDescriptionHash(
        OutputDescription calldata output
    ) internal pure returns (bytes32) {
        return keccak256(encodeOutputDescription(output));
    }

    /**
     * @notice Converts a common payload slice into an output hash. This is possible because both the
     * output hash and the common payload have a shared chunk of data. It only has to be enhanced with
     * remoteOracle and chain id and then hashed.
     */
    function getOutputDescriptionHash(bytes32 remoteOracle, uint256 chainId, bytes calldata commonPayload) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(remoteOracle, chainId, commonPayload));
    }

    // --- FillDescription Encoding --- //

    /**
     * @notice FillDescription encoding.
     */
    function encodeFillDescription(
        bytes32 solver,
        bytes32 orderId,
        uint32 timestamp,
        bytes32 token,
        uint256 amount,
        bytes32 recipient,
        bytes memory remoteCall,
        bytes memory fulfillmentContext
    ) internal pure returns (bytes memory encodedOutput) {
        // Check that the length of remoteCall & fulfillmentContext does not exceed type(uint16).max
        if (remoteCall.length > type(uint16).max) revert RemoteCallOutOfRange();
        if (fulfillmentContext.length > type(uint16).max) revert FulfillmentContextCallOutOfRange();

        return encodedOutput = abi.encodePacked(
            solver,
            orderId,
            timestamp,
            token,
            amount,
            recipient,
            uint16(remoteCall.length), // To protect against data collisions
            remoteCall,
            uint16(fulfillmentContext.length), // To protect against data collisions
            fulfillmentContext
        );
    }

    /**
     * @notice Encodes an output description into a fill description.
     * @dev A fill description doesn't contain a description of the remote (remoteOracle or chainid)
     * because these are attached to the package. Instead the fill description describes
     * how the order was filled. These have to be collected externally.
     */
    function encodeFillDescription(bytes32 solver, bytes32 orderId, uint32 timestamp, OutputDescription calldata outputDescription) internal pure returns (bytes memory encodedOutput) {
        return encodedOutput =
            encodeFillDescription(solver, orderId, timestamp, outputDescription.token, outputDescription.amount, outputDescription.recipient, outputDescription.remoteCall, outputDescription.fulfillmentContext);
    }

    function encodeFillDescriptionM(bytes32 solver, bytes32 orderId, uint32 timestamp, OutputDescription memory outputDescription) internal pure returns (bytes memory encodedOutput) {
        return encodedOutput =
            encodeFillDescription(solver, orderId, timestamp, outputDescription.token, outputDescription.amount, outputDescription.recipient, outputDescription.remoteCall, outputDescription.fulfillmentContext);
    }

    // -- FillDescription Decoding Helpers -- //

    function decodeFillDescriptionSolver(
        bytes calldata payload
    ) internal pure returns (bytes32 solver) {
        assembly ("memory-safe") {
            // solver = bytes32(payload[0:32]);
            solver := calldataload(payload.offset)
        }
    }

    function decodeFillDescriptionOrderId(
        bytes calldata payload
    ) internal pure returns (bytes32 orderId) {
        assembly ("memory-safe") {
            // orderId = bytes32(payload[32:64]);
            orderId := calldataload(add(payload.offset, 32))
        }
    }

    function decodeFillDescriptionTimestamp(
        bytes calldata payload
    ) internal pure returns (uint32) {
        bytes4 payloadTimestamp;
        assembly ("memory-safe") {
            // payloadTimestamp = bytes4(payload[64:68]);
            payloadTimestamp := calldataload(add(payload.offset, 64))
        }
        return uint32(payloadTimestamp);
    }

    function decodeFillDescriptionCommonPayload(
        bytes calldata payload
    ) internal pure returns (bytes calldata remainingPayload) {
        return remainingPayload = payload[68:];
    }
}
