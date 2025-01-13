// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { FillDeadlineFarInFuture, FillDeadlineInPast, WrongChain, WrongRemoteOracle } from "../interfaces/Errors.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { OutputDescription } from "../reactors/CatalystOrderType.sol";
import { IdentifierLib } from "../libs/IdentifierLib.sol";

abstract contract BaseOracle is IOracle {
    error NotProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 dataHash);
    error NotDivisible(uint256 value, uint256 divisor);
    error BadDeploymentAddress(address);

    /**
     * @notice Maps filled outputs to solvers.
     * @dev Outputs aren't parsed and it is the consumer's responsibility the hash is of data that makes sense.
     */
    mapping(uint256 remoteChainId => mapping(bytes32 senderIdentifier => mapping(bytes32 dataHash => bool))) internal _attestations;

    constructor() {
        // It is important that this contract's address is 16 bytes.

        // TODO: This check needs to be reinforced.
        // if (uint256(uint128(uint160(address(this)))) != uint256(uint160(address(this)))) revert BadDeploymentAddress(address(this));
    }

    function getIdentifier(address app) external view returns (bytes32) {
        // TODO: no need to concat.
        return IdentifierLib.getIdentifier(app, address(uint160(uint128(uint160(address(this))))));
    }

    //--- Data Attestation Validation ---//

    /**
     * @notice Check if a remote oracle has attested to some data
     * @dev Helper function for accessing _attestations.
     * @param remoteChainId Chain the data supposedly originated from.
     * @param remoteOracle Identifier for the remote attestation.
     * @param dataHash Hash of data.
     */
    function _isProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 dataHash) internal view returns (bool) {
        return _attestations[remoteChainId][remoteOracle][dataHash];
    }

    /**
     * @notice Check if some data has been attested to.
     * @param remoteChainId Chain the data supposedly originated from.
     * @param remoteOracle Identifier for the remote attestation.
     * @param dataHash Hash of data.
     */
    function isProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 dataHash) external view returns (bool) {
        return _isProven(remoteChainId, remoteOracle, dataHash);
    }

    /**
     * @notice Check if a series of data has been attested to.
     * @dev Lengths of arrays aren't checked. Ensure they are sane before calling.
     * @param remoteChainIds Chain the data supposedly originated from.
     * @param remoteOracles Identifier for the remote attestation.
     * @param dataHashs Hash of data.
     */
    function isProven(uint256[] calldata remoteChainIds, bytes32[] calldata remoteOracles, bytes32[] calldata dataHashs) external view returns (bool) {
        uint256 series = remoteOracles.length;
        // Check that the rest of the outputs have been filled.
        // Notice that we discard the solver address and only check if it has been set
        for (uint256 i = 1; i < series; ++i) {
            bool state = _isProven(remoteChainIds[i], remoteOracles[i], dataHashs[i]);
            if (!state) return false;
        }
        return true;
    }

    /**
     * @notice Check if a series of data has been attested to.
     * @dev More efficient implementation of requireProven.
     * @param proofSeries remoteOracle, remoteChainId, and dataHash encoded in chucks of 32*3=96 bytes.
     */
    function efficientRequireProven(bytes calldata proofSeries) external view {
        unchecked {
            // Get the number of proof series.
            uint256 proofBytes = proofSeries.length;
            uint256 series = proofBytes / (32*3);
            if (series * (32*3) != proofBytes) revert NotDivisible(proofBytes, 32*3);

            // Go over the data. We will use an for loop iterating over the offset.
            for (uint256 offset; offset < proofBytes;) {
                uint256 remoteChainId = uint256(bytes32(proofSeries[offset: offset += 32]));
                bytes32 remoteOracle = bytes32(proofSeries[offset: offset += 32]);
                bytes32 dataHash = bytes32(proofSeries[offset: offset += 32]);
                bool state = _isProven(remoteChainId, remoteOracle, dataHash);
                if (!state) revert NotProven(remoteChainId, remoteOracle, dataHash);
            }
        }
    }
}
