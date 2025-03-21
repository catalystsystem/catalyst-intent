// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "solady/auth/Ownable.sol";

import { BaseOracle } from "../BaseOracle.sol";
import { ICrossL2Prover } from "./ICrossL2Prover.sol";
import { OutputDescription, OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

/**
 * @notice Polymer Oracle that uses the fill event to reconstruct the payload for verification.
 */
contract PolymerOracle is BaseOracle, Ownable {
    error AlreadySet();
    error ZeroValue();

    event MapMessagingProtocolIdentifierToChainId(uint32 messagingProtocolIdentifier, uint256 chainId);

    mapping(uint32 messagingProtocolChainIdentifier => uint256 blockChainId) _chainIdentifierToBlockChainId;
    /**
     * @dev The map is bi-directional.
     */
    mapping(uint256 blockChainId => uint32 messagingProtocolChainIdentifier) _blockChainIdToChainIdentifier;

    ICrossL2Prover CROSS_L2_PROVER;

    constructor(address _owner, address crossL2Prover) {
        _initializeOwner(_owner);
        CROSS_L2_PROVER = ICrossL2Prover(crossL2Prover);
    }

    // --- Chain ID Functions --- //

    /**
     * @notice Sets an immutable map of the identifier messaging protocols use to chain ids.
     * @dev Can only be called once for every chain.
     * @param messagingProtocolChainIdentifier Messaging provider identifier for a chain.
     * @param chainId Most common identifier for a chain. For EVM, it can often be accessed through block.chainid.
     */
    function setChainMap(uint32 messagingProtocolChainIdentifier, uint256 chainId) external onlyOwner {
        // Check that the inputs haven't been mistakenly called with 0 values.
        if (abi.encodePacked(messagingProtocolChainIdentifier).length == 0) revert ZeroValue();
        if (chainId == 0) revert ZeroValue();

        // This call only allows setting either value once, then they are done for.
        // We need to check if they are currently unset.
        if (_chainIdentifierToBlockChainId[messagingProtocolChainIdentifier] != 0) revert AlreadySet();
        if (abi.encodePacked(_blockChainIdToChainIdentifier[chainId]).length != 0) revert AlreadySet();

        _chainIdentifierToBlockChainId[messagingProtocolChainIdentifier] = chainId;
        _blockChainIdToChainIdentifier[chainId] = messagingProtocolChainIdentifier;

        emit MapMessagingProtocolIdentifierToChainId(messagingProtocolChainIdentifier, chainId);
    }

    /**
     * @param messagingProtocolChainIdentifier Messaging protocol chain identifier
     * @return chainId Common chain identifier
     */
    function getChainIdentifierToBlockChainId(
        uint32 messagingProtocolChainIdentifier
    ) external view returns (uint256 chainId) {
        return _chainIdentifierToBlockChainId[messagingProtocolChainIdentifier];
    }

    /**
     * @param chainId Common chain identifier
     * @return messagingProtocolChainIdentifier Messaging protocol chain identifier.
     */
    function getBlockChainIdToChainIdentifier(
        uint256 chainId
    ) external view returns (uint32 messagingProtocolChainIdentifier) {
        return _blockChainIdToChainIdentifier[chainId];
    }

    function _proofPayloadHash(bytes32 orderId, bytes32 solver, uint32 timestamp, OutputDescription memory outputDescription) internal pure returns (bytes32 outputHash) {
        return outputHash = keccak256(OutputEncodingLib.encodeFillDescriptionM(solver, orderId, timestamp, outputDescription));
    }

    function _processMessage(
        bytes calldata proof
    ) internal {
        (uint32 chainId, address emittingContract, bytes memory topics, bytes memory unindexedData) = CROSS_L2_PROVER.validateEvent(proof);

        // Store payload attestations;
        bytes32 orderId = bytes32(topics[0]);

        (bytes32 solver, uint32 timestamp, OutputDescription memory output) = abi.decode(unindexedData, (bytes32, uint32, OutputDescription));

        bytes32 payloadHash = _proofPayloadHash(orderId, solver, timestamp, output);

        // Convert the Polymer ChainID into the canonical chainId.
        uint256 remoteChainId = _chainIdentifierToBlockChainId[chainId];
        bytes32 senderIdentifier = bytes32(uint256(uint160(emittingContract)));
        _attestations[remoteChainId][bytes32(0)][senderIdentifier][payloadHash] = true;

        emit OutputProven(remoteChainId, bytes32(0), senderIdentifier, payloadHash);
    }

    function receiveMessage(
        bytes calldata proof
    ) external {
        _processMessage(proof);
    }

    function receiveMessage(
        bytes[] calldata proofs
    ) external {
        uint256 numProofs = proofs.length;
        for (uint256 i; i < numProofs; ++i) {
            _processMessage(proofs[i]);
        }
    }
}
