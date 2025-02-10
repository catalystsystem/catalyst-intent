// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { IOracle } from "src/interfaces/IOracle.sol";

/**
 * @notice Foundation for oracles. Exposes attesation logic for consumers.
 * @dev Ideally the contract has a 16 bytes address, that is 4 bytes have been mined for 0s.
 */
abstract contract BaseOracle is IOracle {
    error NotDivisible(uint256 value, uint256 divisor);
    error NotProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 application, bytes32 dataHash);

    event OutputProven(uint256 chainid, bytes32 remoteIdentifier, bytes32 application, bytes32 payloadHash);

    /**
     * @notice Stores payload attestations. Payloads are not stored, instead their hashes are.
     */
    mapping(uint256 remoteChainId => mapping(bytes32 senderIdentifier => mapping(bytes32 application => mapping(bytes32 dataHash => bool)))) internal _attestations;

    //--- Data Attestation Validation ---//

    /**
     * @notice Check if a remote oracle has attested to some data
     * @dev Helper function for accessing _attestations.
     * @param remoteChainId Origin chain of the supposed data.
     * @param remoteOracle Identifier for the remote attestation.
     * @param dataHash Hash of data.
     */
    function _isProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 application, bytes32 dataHash) internal view returns (bool) {
        return _attestations[remoteChainId][remoteOracle][application][dataHash];
    }

    /**
     * @notice Check if a remote oracle has attested to some data
     * @param remoteChainId Origin chain of the supposed data.
     * @param remoteOracle Identifier for the remote attestation.
     * @param dataHash Hash of data.
     */
    function isProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 application, bytes32 dataHash) external view returns (bool) {
        return _isProven(remoteChainId, remoteOracle, application, dataHash);
    }

    /**
     * @notice Check if a series of data has been attested to.
     * @dev More efficient implementation of requireProven. Does not return a boolean, instead reverts if false.
     * This function returns true if proofSeries is empty.
     * @param proofSeries remoteOracle, remoteChainId, and dataHash encoded in chucks of 32*4=128 bytes.
     */
    function efficientRequireProven(
        bytes calldata proofSeries
    ) external view {
        unchecked {
            // Get the number of proof series.
            uint256 proofBytes = proofSeries.length;
            uint256 series = proofBytes / (32 * 4);
            if (series * (32 * 4) != proofBytes) revert NotDivisible(proofBytes, 32 * 4);

            // Go over the data. We will use a for loop iterating over the offset.
            for (uint256 offset; offset < proofBytes;) {
                // Load the proof description.
                uint256 remoteChainId;
                bytes32 remoteOracle;
                bytes32 application;
                bytes32 dataHash;
                // Load variables from calldata to save gas compared to slices.
                assembly ("memory-safe") {
                    remoteChainId := calldataload(add(proofSeries.offset, offset))
                    offset := add(offset, 0x20)
                    remoteOracle := calldataload(add(proofSeries.offset, offset))
                    offset := add(offset, 0x20)
                    application := calldataload(add(proofSeries.offset, offset))
                    offset := add(offset, 0x20)
                    dataHash := calldataload(add(proofSeries.offset, offset))
                    offset := add(offset, 0x20)
                }
                bool state = _isProven(remoteChainId, remoteOracle, application, dataHash);
                if (!state) revert NotProven(remoteChainId, remoteOracle, application, dataHash);
            }
        }
    }
}
