// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IOracle {
    /**
     * @notice Check if some data has been attested to.
     * @param remoteChainId Chain the data supposedly originated from.
     * @param remoteOracle Identifier for the remote attestation.
     * @param dataHash Hash of data.
     */
    function isProven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 dataHash) external view returns (bool);

    /**
     * @notice Check if a series of data has been attested to.
     * @dev Lengths of arrays aren't checked. Ensure they are sane before calling.
     * @param remoteChainIds Chain the data supposedly originated from.
     * @param remoteOracles Identifier for the remote attestation.
     * @param dataHashes Hash of data.
     */
    function isProven(uint256[] calldata remoteChainIds, bytes32[] calldata remoteOracles, bytes32[] calldata dataHashes) external view returns (bool);

    /**
     * @notice Reverts if a series of data has not been attested to.
     * @dev More efficient implementation of requireProven.
     * @param proofSeries remoteChainId, remoteOracle,and dataHash encoded in chucks of 32*3=96 chunks.
     */
    function efficientRequireProven(
        bytes calldata proofSeries
    ) external view;
}
