// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IOracle {
    /**
     * @notice Check if some data has been attested to.
     * @param remoteChainId Chain the data supposedly originated from.
     * @param remoteOracle Identifier for the remote attestation.
     * @param remoteApplication Identifier for the application that the attestation originated from.
     * @param dataHash Hash of data.
     */
    function isProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 remoteApplication, bytes32 dataHash) external view returns (bool);

    /**
     * @notice Reverts if a series of data has not been attested to.
     * @dev More efficient implementation of requireProven.
     * @param proofSeries remoteChainId, remoteOracle,and dataHash encoded in chucks of 32*3=96 chunks.
     */
    function efficientRequireProven(
        bytes calldata proofSeries
    ) external view;
}
