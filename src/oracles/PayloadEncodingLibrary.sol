// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

library PayloadEncodingLibrary {
    error PayloadTooLarge(uint256 size);

    function encodeMessage(
        bytes32 identifier,
        bytes[] calldata payloads
    ) internal pure returns (bytes memory encodedPayload) {
        uint256 numPayloads = payloads.length;
        // Set the number of outputs as first 2 bytes. This aids implementations which may not have easy access to data size
        encodedPayload = bytes.concat(identifier, bytes2(uint16(numPayloads)));
        unchecked {
            for (uint256 i; i < numPayloads; ++i) {
                bytes memory payload = payloads[i];
                // Check if length of payload is within message constraints.
                uint256 payloadLength = payload.length;
                if (payloadLength > type(uint16).max) revert PayloadTooLarge(payloadLength);
                encodedPayload = abi.encodePacked(
                    encodedPayload,
                    uint16(payloadLength),
                    payload
                );
            }
        }
    }

    /** @dev Hashes payloads to reduce memory expansion costs. */
    function decodeMessage(
        bytes calldata encodedPayload
    ) internal pure returns (bytes32 identifier, bytes32[] memory payloadHashes) {
        unchecked {
            identifier = bytes32(encodedPayload[0:32]);
            uint256 numPayloads = uint256(uint16(bytes2(encodedPayload[32:34])));

            payloadHashes = new bytes32[](numPayloads);
            uint256 pointer = 34;
            for (uint256 index = 0; index < numPayloads; ++index) {
                // Don't allow overflows here. Otherwise you could cause some serious harm.
                uint256 payloadSize = uint256(uint16(bytes2(encodedPayload[pointer:pointer += 2])));
                bytes calldata payload = encodedPayload[pointer:pointer += payloadSize];

                // The payload is hashed immediately to reduce memory expansion costs.
                bytes32 hashedPayload = keccak256(payload);
                payloadHashes[index] = hashedPayload;
            }
        }
    }
}
