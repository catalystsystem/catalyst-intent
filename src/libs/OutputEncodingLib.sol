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

 *  //TODO this name is confusing (vs common/remaining payload)
 *  Payload (Used as a portable format that can prove what happened on the remote chain)
 *      SOLVER                          0               (32 bytes)
 *      + ORDERID                       32              (32 bytes)
 *      + FILL_RECORD_LENGTH            64              (1 bytes)
 *      + FILL_RECORD                   65              (LENGTH bytes)
 *
 * Common Payload. Is identical between both encoding scheme
 *      + TOKEN                         Y               (32 bytes)
 *      + AMOUNT                        Y+32            (32 bytes)
 *      + RECIPIENT                     Y+64            (32 bytes)
 *      + REMOTE_CALL_LENGTH            Y+96            (2 bytes)
 *      + REMOTE_CALL                   Y+98            (LENGTH bytes)
 *      + FULFILLMENT_CONTEXT_LENGTH    Y+98+RC_LENGTH  (2 bytes)       //TODO is this needed?
 *      + FULFILLMENT_CONTEXT           Y+100+RC_LENGTH (LENGTH bytes)  //TODO is this needed?
 *
 * where Y is the offset from the specific encoding (either 64 or 69)
 *
 */

//TODO this library does a mixture of different things, it is hard to understand. Can it be split up? (e.g. remove hashing/only encode 1 type of data)
library OutputEncodingLib {
    error RemoteCallOutOfRange();
    error fulfillmentContextCallOutOfRange();   //TODO initial letter case

    // --- OutputDescription Encoding --- //

    /** 
     * @notice Creates a unique hash of an OutputDescription
     * @dev This does provide a description of how an output was filled but just
     * an exact unique identifier for an output description. This identifier is
     * purely intended for the remote chain.
     */
    function outputHash(OutputDescription calldata output) pure internal returns(bytes32) {
        return keccak256(encodeEntireOutput(output));
    }

    function outputHashMemory(OutputDescription memory output) pure internal returns(bytes32) {
        return keccak256(encodeEntireOutput(output));
    }
    
    /** 
     * @notice Predictable encoding of outputDescription that deliberately overlaps with the payload encoding.
     * @dev This function uses length identifiers 2 bytes long. As a result, neither remoteCall nor fulfillmentContext
     * can be larger than 65535.
     */
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

    /**
     * @notice Converts a payload slice into an output hash. This is possible because both the
     * output hash and payload have a shared chunk of data. It only have to be enhanced with
     * remoteOracle and chain id and then hashed.
     */
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

    /**
     * @notice Payload encoding.
     */
    function encodeOutput(
        bytes32 solver,
        bytes32 orderId,
        bytes memory fillRecord,    //TODO can this be calldata?
        bytes32 token,
        uint256 amount,
        bytes32 recipient,
        bytes memory remoteCall,
        bytes memory fulfillmentContext
    ) internal pure returns (bytes memory encodedOutput) {
        // Check that the length of remoteCall & fulfillmentContext does not exceed type(uint16).max
        if (fillRecord.length > type(uint8).max) revert fulfillmentContextCallOutOfRange();    //TODO use a custom error
        if (remoteCall.length > type(uint16).max) revert RemoteCallOutOfRange();
        if (fulfillmentContext.length > type(uint16).max) revert fulfillmentContextCallOutOfRange();

        return encodedOutput = abi.encodePacked(
            solver,
            orderId,
            uint8(fillRecord.length),
            fillRecord,
            token,
            amount,
            recipient,
            uint16(remoteCall.length), // To protect against data collisions
            remoteCall,
            uint16(fulfillmentContext.length), // To protect against data collisions
            fulfillmentContext
        );
    }

    //TODO If this function is the same as `encodeOutput`, just with different parameters, use function overloading (i.e. give it the same name)
    /**
     * @notice Encodes an output description into a payload.
     * @dev A payload doesn't contain a description of the remote (remoteOracle or chainid)
     * because these are attached to the package. Instead the payload contains a description of
     * how the order was filled. These have to be collected externally.
     */
    function encodeOutputDescriptionIntoPayload(
        bytes32 solver,
        bytes32 orderId,
        bytes memory fillRecord,    //TODO can this be calldata?
        OutputDescription memory outputDescription
    ) internal pure returns (bytes memory encodedOutput) {

        return encodedOutput = encodeOutput(
            solver,
            orderId,
            fillRecord,
            outputDescription.token,
            outputDescription.amount,
            outputDescription.recipient,
            outputDescription.remoteCall,
            outputDescription.fulfillmentContext
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

    function decodePayloadOrderId(
        bytes calldata payload
    ) internal pure returns (bytes32 orderId) {
        assembly ("memory-safe") {
            // orderId = bytes32(payload[37:69]);
            orderId := calldataload(add(payload.offset, 32))
        }
    }

    function decodePayloadFillRecord(
        bytes calldata payload
    ) internal pure returns (bytes calldata fillRecord) {
        uint8 fillRecordLength = uint8(payload[64]);
        return payload[65:65 + fillRecordLength];
    }

    function selectRemainingPayload(
        bytes calldata payload
    ) internal pure returns (bytes calldata remainingPayload) {
        uint8 fillRecordLength = uint8(payload[64]);
        return remainingPayload = payload[65 + fillRecordLength:];
    }
}
