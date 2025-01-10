// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { FillDeadlineFarInFuture, FillDeadlineInPast, WrongChain, WrongRemoteOracle } from "../interfaces/Errors.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { OutputDescription } from "../libs/CatalystOrderType.sol";

abstract contract BaseOracle is IOracle {
    error NotProven(bytes32 remoteOracle, bytes32 remoteChainId, bytes32 dataHash);
    error NotDivisible(uint256 value, uint256 divisor);
    error BadDeploymentAddress(address);

    /**
     * @notice Maps filled outputs to solvers.
     * @dev Outputs aren't parsed and it is the consumer that is responsible the hash is of data that makes sense.
     * If remoteChainId == 0, then it belongs to a sender from this chain.
     */
    mapping(bytes32 remoteChainId => mapping(bytes32 senderIdentifier => mapping(bytes32 dataHash => bool))) internal _attestations;

    constructor() {
        // It is important that this contract's address is 16 bytes.
        if (uint256(uint128(uint160(address(this)))) != uint256(uint160(address(this)))) revert BadDeploymentAddress(address(this));
    }

    /**
     * @notice Computes a identifier for the route.
     * The first 16 bytes is of the original origin.
     * The last 16 bytes is of this contract.
     * @dev This identifier requries that both this contract
     * and the app has been mined for 16 bytes addresses. Otherwise there may be collisions.
     */
    function _getIdentifier(address app) internal view returns (bytes32) {
        // Because of the deployment constraint we do not need to cleanup address(this)
        return bytes32(uint256(uint128(uint160(app))) >> 128 + uint256(uint160(address(this))));
    }

    function getIdentifier(address app) external view returns (bytes32) {
        return _getIdentifier(app);
    }

    function _enhanceIdentifier(bytes32 identifierFromCourier, bytes32 identifierFromMessage) internal pure returns (bytes32) {
        if (identifierFromCourier == identifierFromMessage) return identifierFromMessage;

        // Check if the identifierFromCourier is parital:
        if (uint256(identifierFromCourier) < uint256(type(uint128).max)) {
            // If the last 16 bytes match, then identifierFromMessage must be the valid one.
            if (uint256(identifierFromCourier) == uint128(uint256(identifierFromMessage))) return identifierFromMessage;
        }
        return identifierFromCourier;
    }

    //--- Data Attestation Validation ---//

    /**
     * @notice Check if a remote oracle has attested to some data
     * @dev Helper function for accessing _attestations.
     * @param remoteChainId Chain the data supposedly originated from.
     * @param remoteOracle Identifier for the remote attestation.
     * @param dataHash Hash of data.
     */
    function _isProven(bytes32 remoteChainId, bytes32 remoteOracle, bytes32 dataHash) internal view returns (bool state) {
        state = _attestations[remoteChainId][remoteOracle][dataHash];
    }

    /**
     * @notice Check if some data has been attested to.
     * @param remoteChainId Chain the data supposedly originated from.
     * @param remoteOracle Identifier for the remote attestation.
     * @param dataHash Hash of data.
     */
    function isProven(bytes32 remoteOracle, bytes32 remoteChainId, bytes32 dataHash) external view returns (bool) {
        return _isProven(remoteOracle, remoteChainId, dataHash);
    }

    /**
     * @notice Reverts if some data has not been attested to.
     * @param remoteChainId Chain the data supposedly originated from.
     * @param remoteOracle Identifier for the remote attestation.
     * @param dataHash Hash of data.
     */
    function requireProven(bytes32 remoteOracle, bytes32 remoteChainId, bytes32 dataHash) external view {
        if (!_isProven(remoteOracle, remoteChainId, dataHash)) revert NotProven(remoteOracle, remoteChainId, dataHash);
    }

    /**
     * @notice Check if a series of data has been attested to.
     * @dev Lengths of arrays aren't checked. Ensure they are sane before calling.
     * @param remoteChainIds Chain the data supposedly originated from.
     * @param remoteOracles Identifier for the remote attestation.
     * @param dataHashs Hash of data.
     */
    function isProven(bytes32[] calldata remoteOracles, bytes32[] calldata remoteChainIds, bytes32[] calldata dataHashs) external view returns (bool) {
        uint256 series = remoteOracles.length;
        // Check that the rest of the outputs have been filled.
        // Notice that we discard the solver address and only check if it has been set
        for (uint256 i = 1; i < series; ++i) {
            bool state = _isProven(remoteOracles[i], remoteChainIds[i], dataHashs[i]);
            if (!state) return false;
        }
        return true;
    }

    /**
     * @notice Check if a series of data has been attested to.
     * @dev Lengths of arrays aren't checked. Ensure they are sane before calling.
     * @param remoteChainIds Chain the data supposedly originated from.
     * @param remoteOracles Identifier for the remote attestation.
     * @param dataHashs Hash of data.
     */
    function requireProven(bytes32[] calldata remoteOracles, bytes32[] calldata remoteChainIds, bytes32[] calldata dataHashs) external view {
        uint256 series = remoteOracles.length;
        // Check that the rest of the outputs have been filled.
        // Notice that we discard the solver address and only check if it has been set
        for (uint256 i = 1; i < series; ++i) {
            bool state = _isProven(remoteOracles[i], remoteChainIds[i], dataHashs[i]);
            if (!state) revert NotProven(remoteOracles[i], remoteChainIds[i], dataHashs[i]);
        }
    }

    /**
     * @notice Check if a series of data has been attested to.
     * @dev More efficient implementation of requireProven.
     * @param proofSeries remoteOracle, remoteChainId, and dataHash encoded in chucks of 32*3=96 chunks.
     */
    function efficientRequireProven(bytes calldata proofSeries) external view {
        // Get the number of proof series.
        uint256 proofBytes = proofSeries.length;
        uint256 series = proofBytes / (32*3);
        if (series * (32*3) != proofBytes) revert NotDivisible(proofBytes, 32*3);

        // Go over the data. We will use an for loop iterating over the offset.
        for (uint256 offset; offset < proofBytes;) {
            unchecked {
                bytes32 remoteOracle = bytes32(proofSeries[offset: offset += 32]);
                bytes32 remoteChainId = bytes32(proofSeries[offset: offset += 32]);
                bytes32 dataHash = bytes32(proofSeries[offset: offset += 32]);
                bool state = _isProven(remoteOracle, remoteChainId, dataHash);
                if (!state) revert NotProven(remoteOracle, remoteChainId, dataHash);
            }
        }
    }

    function storeProof(bytes32 dataHash) public returns (bool beforeState) {
        beforeState = _attestations[bytes32(0)][bytes32(uint256(uint160(msg.sender)))][dataHash];
        if (!beforeState) _attestations[bytes32(0)][bytes32(uint256(uint160(msg.sender)))][dataHash] = true;
    }
}
