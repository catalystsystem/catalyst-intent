// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { FillDeadlineFarInFuture, FillDeadlineInPast, WrongChain, WrongRemoteOracle } from "../interfaces/Errors.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { OutputDescription } from "../reactors/CatalystOrderType.sol";
import { IdentifierLib } from "../libs/IdentifierLib.sol";

/**
 * @notice Foundation for oracles. Exposes attesation logic for consumers.
 * @dev Ideally the contract has a 16 bytes address, that is 4 bytes have been mined for 0s.
 */
abstract contract BaseOracle is IOracle {
    error NotProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 dataHash);
    error NotDivisible(uint256 value, uint256 divisor);
    error BadDeploymentAddress(address);
    
    event OutputProven(uint256 chainid, bytes32 remoteIdentifier, bytes32 payloadHash);

    /** @notice Stores payload attestations. Payloads are not stored, instead their hashes are. */
    mapping(uint256 remoteChainId => mapping(bytes32 senderIdentifier => mapping(bytes32 dataHash => bool))) internal _attestations;

    /** @notice Given an app, returns the combined identifier of both protocols. */
    function getIdentifier(address app) external view returns (bytes32) {
        return IdentifierLib.getIdentifier(app, address(this));
    }

    //--- Data Attestation Validation ---//

    /**
     * @notice Check if a remote oracle has attested to some data
     * @dev Helper function for accessing _attestations.
     * @param remoteChainId Origin chain of the supposed data.
     * @param remoteOracle Identifier for the remote attestation.
     * @param dataHash Hash of data.
     */
    function _isProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 dataHash) internal view returns (bool) {
        return _attestations[remoteChainId][remoteOracle][dataHash];
    }

    /**
     * @notice Check if a remote oracle has attested to some data
     * @param remoteChainId Origin chain of the supposed data.
     * @param remoteOracle Identifier for the remote attestation.
     * @param dataHash Hash of data.
     */
    function isProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 dataHash) external view returns (bool) {
        return _isProven(remoteChainId, remoteOracle, dataHash);
    }

    /**
     * @notice Check if a series of data has been attested to.
     * @dev Lengths of arrays aren't checked. Ensure they are sane before calling.
     * @param remoteChainIds Origin chain of the supposed data.
     * @param remoteOracles Identifier for the remote attestation.
     * @param dataHashs Hash of data.
     */
    function isProven(uint256[] calldata remoteChainIds, bytes32[] calldata remoteOracles, bytes32[] calldata dataHashs) external view returns (bool) {
        uint256 series = remoteOracles.length;
        // Check that the rest of the outputs have been filled.
        // Notice that we discard the solver address and only check if it has been set
        for (uint256 i = 0; i < series; ++i) {
            bool state = _isProven(remoteChainIds[i], remoteOracles[i], dataHashs[i]);
            if (!state) return false;
        }
        return true;
    }

    /**
     * @notice Check if a series of data has been attested to.
     * @dev More efficient implementation of requireProven. Does not return a boolean, instead reverts if false.
     * @param proofSeries remoteOracle, remoteChainId, and dataHash encoded in chucks of 32*3=96 bytes.
     */
    function efficientRequireProven(bytes calldata proofSeries) external view {
        unchecked {
            // Get the number of proof series.
            uint256 proofBytes = proofSeries.length;
            uint256 series = proofBytes / (32*3);
            if (series * (32*3) != proofBytes) revert NotDivisible(proofBytes, 32*3);

            // Go over the data. We will use a for loop iterating over the offset.
            for (uint256 offset; offset < proofBytes;) {
                // Load the proof description.
                uint256 remoteChainId;
                bytes32 remoteOracle;
                bytes32 dataHash;
                // Load variables from calldata to save gas compared to slices.
                assembly ("memory-safe") {
                    remoteChainId := calldataload(add(proofSeries.offset, offset))
                    offset := add(offset, 0x20)
                    remoteOracle := calldataload(add(proofSeries.offset, offset))
                    offset := add(offset, 0x20)
                    dataHash := calldataload(add(proofSeries.offset, offset))
                    offset := add(offset, 0x20)
                }
                bool state = _isProven(remoteChainId, remoteOracle, dataHash);
                if (!state) revert NotProven(remoteChainId, remoteOracle, dataHash);
            }
        }
    }
}
