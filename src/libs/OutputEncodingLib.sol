// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

struct OutputDescription {
    /**
     * @dev Contract on the destination that tells whether an order was filled.
     */
    bytes32 remoteOracle;
    /**
     * @dev Contract on the destination that contains logic to resolve this output
     */
    bytes32 remoteFiller;
    /**
     * @dev The destination chain for this output.
     */
    uint256 chainId;
    /**
     * @dev The address of the token on the destination chain.
     */
    bytes32 token;
    /**
     * @dev The amount of the token to be sent.
     */
    uint256 amount;
    /**
     * @dev The address to receive the output tokens.
     */
    bytes32 recipient;
    /**
     * @dev Additional data that will be used to execute a call on the remote chain.
     * Is called on recipient.
     */
    bytes remoteCall;
    /**
     * @dev Non-particular data that is used to encode non-generic behaviour for a filler.
     */
    bytes fulfillmentContext;
}

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
 *      + REMOTE_FILLER                 32              (32 bytes)
 *      + CHAIN_ID                      64              (32 bytes)
 *      + COMMON_PAYLOAD                96
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
 * where Y is the offset from the specific encoding (either 68 or 96)
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
            outputDescription.remoteFiller,
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

    function encodeOutputDescriptionMemory(
        OutputDescription memory outputDescription
    ) internal pure returns (bytes memory encodedOutput) {
        bytes memory remoteCall = outputDescription.remoteCall;
        bytes memory fulfillmentContext = outputDescription.fulfillmentContext;
        // Check that the length of remoteCall & fulfillmentContext does not exceed type(uint16).max
        if (remoteCall.length > type(uint16).max) revert RemoteCallOutOfRange();
        if (fulfillmentContext.length > type(uint16).max) revert FulfillmentContextCallOutOfRange();

        return encodedOutput = abi.encodePacked(
            outputDescription.remoteOracle,
            outputDescription.remoteFiller,
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

    function getOutputDescriptionHashMemory(
        OutputDescription memory output
    ) internal pure returns (bytes32) {
        return keccak256(encodeOutputDescriptionMemory(output));
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
    function encodeFillDescription(
        bytes32 solver,
        bytes32 orderId,
        uint32 timestamp,
        OutputDescription calldata outputDescription
    ) internal pure returns (bytes memory encodedOutput) {
        return encodedOutput = encodeFillDescription(
            solver,
            orderId,
            timestamp,
            outputDescription.token,
            outputDescription.amount,
            outputDescription.recipient,
            outputDescription.remoteCall,
            outputDescription.fulfillmentContext
        );
    }

    function encodeFillDescriptionM(
        bytes32 solver,
        bytes32 orderId,
        uint32 timestamp,
        OutputDescription memory outputDescription
    ) internal pure returns (bytes memory encodedOutput) {
        return encodedOutput = encodeFillDescription(
            solver,
            orderId,
            timestamp,
            outputDescription.token,
            outputDescription.amount,
            outputDescription.recipient,
            outputDescription.remoteCall,
            outputDescription.fulfillmentContext
        );
    }
}
