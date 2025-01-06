// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./OraclePayload.sol";
import { BaseOracle } from "./BaseOracle.sol";
import { OutputDescription } from "../libs/CatalystOrderType.sol";

/**
 * @dev Oracles are also fillers
 */
library OutputEncodingLibrary {
    error RemoteCallOutOfRange();
    error fulfillmentContextOutOfRange();
    error EncodedOutputDescriptionOutOfRange();

    // --- Hashing Encoding --- //

    function _encodeOutput(
        uint8 orderType,
        bytes32 token,
        uint256 amount,
        bytes32 recipient,
        uint256 chainId,
        bytes calldata remoteCall,
        bytes calldata fulfillmentContext
    ) internal pure returns (bytes memory encodedOutput) {
        // Check that the remoteCall and fulfillmentContext does not exceed type(uint16).max
        if (remoteCall.length > type(uint16).max) revert RemoteCallOutOfRange();
        if (fulfillmentContext.length > type(uint16).max) revert fulfillmentContextOutOfRange();

        return encodedOutput = abi.encodePacked(
            orderType,
            token,
            amount,
            recipient,
            chainId,
            uint16(remoteCall.length),
            remoteCall,
            uint16(fulfillmentContext.length),
            fulfillmentContext
        );
    }

    function _encodeOutputDescription(
        OutputDescription calldata outputDescription
    ) internal pure returns (bytes memory encodedOutput) {
        return encodedOutput = _encodeOutput(
            outputDescription.orderType,
            outputDescription.token,
            outputDescription.amount,
            outputDescription.recipient,
            outputDescription.chainId,
            outputDescription.remoteCall,
            outputDescription.fulfillmentContext
        );
    }

    // --- Messaging Encoding --- //

    /**
     * @notice Encodes outputs and fillDeadlines into a bytearray to be sent cross chain.
     * @dev This function reverts if fillDeadlines.length < outputs but not if fillDeadlines.length > outputs.
     * Use with care.
     */
    function _encodeMessage(
        bytes32[] calldata orderIds,
        OutputDescription[] calldata outputs,
        BaseOracle.ProofStorage[] memory proofs
    ) internal pure returns (bytes memory encodedPayload) {
        uint256 numOutputs = outputs.length;
        encodedPayload = bytes.concat(bytes1(0x00), bytes2(uint16(numOutputs)));
        unchecked {
            for (uint256 i; i < numOutputs; ++i) {
                // Check encoded output size
                bytes memory encodedOutput = _encodeOutputDescription(outputs[i]);
                if (encodedOutput.length > type(uint16).max) revert EncodedOutputDescriptionOutOfRange();
                encodedPayload = abi.encodePacked(
                    orderIds[i],
                    proofs[i].solver,
                    proofs[i].timestamp,
                    uint16(encodedOutput.length),
                    encodedOutput
                );
            }
        }
    }

    /**
     * @notice Converts an encoded payload into decoded proof descriptions.
     * @dev Do not use remoteOracle from decoded outputs.
     * encodedPayload does not contain any "security". The payload will be "decoded by fire" as it is expected
     * to be encoded by _encode.
     * If a foreign contract set anything here, it important to only attribute the decoded outputs to that contract
     * to ensure the outputs does not poison other storage. If someone trusts that oracle, it is their problem.
     * @param encodedPayload Payload that has been encoded with _encode. Will be decoded into outputs and fillDeadlines.
     * @return orderIdOutputHashes OrderIds and output hashes.
     * @return proofContext Relevant fill context of the outputs.
     */
    function _decodeMessage(
        bytes calldata encodedPayload
    ) internal pure returns (bytes32[2][] memory orderIdOutputHashes, BaseOracle.ProofStorage[] memory proofContext) {
        unchecked {
            uint256 numOutputs = uint256(uint16(bytes2(encodedPayload[NUM_OUTPUTS_START:NUM_OUTPUTS_END])));

            orderIdOutputHashes = new bytes32[2][](numOutputs);
            proofContext = new BaseOracle.ProofStorage[](numOutputs);

            uint256 pointer = NUM_OUTPUTS_END;
            for (uint256 outputIndex; outputIndex < numOutputs; ++outputIndex) {
                bytes32 orderId = bytes32(encodedPayload[pointer:pointer += (ORDER_ID_END - ORDER_ID_START)]);
                bytes32 solver = bytes32(encodedPayload[pointer:pointer += (SOLVER_END - SOLVER_START)]);
                uint40 timestamp = uint40(bytes5(encodedPayload[pointer:pointer += (TIMESTAMP_END - TIMESTAMP_START)]));
                // outputSize is an attack surface. If you can control it (overflow?), you can inject bad data.
                uint16 outputSize = uint16(bytes2(encodedPayload[pointer:pointer += (OUTPUT_SIZE_END - OUTPUT_SIZE_START)]));
                bytes calldata outputBytes = encodedPayload[pointer:pointer += outputSize];
                bytes32 outputHash = keccak256(outputBytes);

                orderIdOutputHashes[outputIndex] = [orderId, outputHash];
                proofContext[outputIndex] = BaseOracle.ProofStorage({
                    solver: address(uint160(uint256(solver))),
                    timestamp: timestamp
                });
            }
        }
    }
}
