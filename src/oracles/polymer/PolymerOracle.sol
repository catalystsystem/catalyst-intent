// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { BaseOracle } from "../BaseOracle.sol";
import { ICrossL2Prover } from "./ICrossL2Prover.sol";
import { OutputDescription } from  "../../reactors/CatalystOrderType.sol";
import { OutputEncodingLibrary } from  "../../reactors/OutputEncodingLibrary.sol";

/**
 * @notice Polymer Oracle that uses the fill event to reconstruct the payload for verification.
 */
abstract contract PolymerOracle is BaseOracle {
    ICrossL2Prover CROSS_L2_PROVER;

    constructor(address crossL2Prover) {
        CROSS_L2_PROVER = ICrossL2Prover(crossL2Prover);
    }

    function _proofPayloadHash(
        bytes32 orderId,
        bytes32 solver,
        uint40 timestamp,
        OutputDescription memory outputDescription
    ) pure internal returns (bytes32 outputHash) {
        return outputHash = keccak256(OutputEncodingLibrary.encodeOutputDescriptionIntoPayload(solver, timestamp, orderId, outputDescription));
    }

    function _processMessage(
        uint256 logIndex, bytes calldata proof
    ) external {

        (string memory chainId, address emittingContract, bytes[] memory topics, bytes memory unindexedData) = CROSS_L2_PROVER.validateEvent(logIndex, proof);

        // Store payload attestations;
        bytes32 orderId = bytes32(topics[0]);

        (bytes32 solver, uint40 timestamp, OutputDescription memory output) = abi.decode(unindexedData, (bytes32, uint40, OutputDescription));

        bytes32 payloadHash = _proofPayloadHash(orderId, solver, timestamp, output);
        uint256 remoteChainId = uint256(bytes32(bytes(chainId)));
        bytes32 senderIdentifier = bytes32(uint256(uint160(emittingContract)));
        _attestations[remoteChainId][senderIdentifier][payloadHash] = true;

        emit OutputProven(remoteChainId, senderIdentifier, payloadHash);
    }
}
