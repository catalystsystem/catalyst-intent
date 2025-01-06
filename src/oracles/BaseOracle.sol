// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { FillDeadlineFarInFuture, FillDeadlineInPast, WrongChain, WrongRemoteOracle } from "../interfaces/Errors.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";
import { OutputDescription } from "../libs/CatalystOrderType.sol";
import { OutputEncodingLibrary } from "./OutputEncodingLibrary.sol";

/**
 * @dev Oracles are also fillers
 */
abstract contract BaseOracle is IOracle {
    error NotProven(bytes32 orderId, OutputDescription);

    event OutputProven(uint32 fillDeadline, bytes32 outputHash);

    uint256 constant MAX_FUTURE_FILL_TIME = 3 days;

    struct ProofStorage {
        address solver;
        uint40 timestamp;
    }

    /**
     * @notice 
     */
    uint32 public immutable CHAIN_ID = uint32(block.chainid);
    bytes32 immutable ADDRESS_THIS = bytes32(uint256(uint160(address(this))));

    /** 
     * @notice Maps filled outputs to solvers.
     * @dev Outputs aren't parsed and it is the consumer that is responsible the hash is of data that makes sense.
     * 
     */
    mapping(bytes32 orderId => 
        mapping(bytes32 remoteOracle => 
        mapping(bytes32 outputHash => ProofStorage))) internal _provenOutput; // TODO: Add timestamp

    //-- Helpers --//

    /**
     * @notice Validate that the remote oracle address is this oracle.
     * @dev For some oracles, it might be required that you "cheat" and change the encoding here.
     * Don't worry (or do worry) because the other side loads the payload as bytes32(bytes).
     */
    function _IAmRemoteOracle(
        bytes32 remoteOracle
    ) internal view virtual {
        if (ADDRESS_THIS != remoteOracle) revert WrongRemoteOracle(ADDRESS_THIS, remoteOracle);
    }
    
    function _outputHash(OutputDescription calldata outputDescription) pure internal returns (bytes32 outputHash) {
        return outputHash = keccak256(OutputEncodingLibrary._encodeOutputDescription(outputDescription));
    }

    /**
     * @notice Validate that expected chain (@param chainId) matches this chain's chainId (block.chainId)
     * @dev We use the chain's canonical id rather than the messaging protocol id for clarity.
     */
    function _validateChain(
        bytes32 chainId
    ) internal view {
        if (block.chainid != uint256(chainId)) revert WrongChain(block.chainid, uint256(chainId));
    }

    //--- Output Proofs ---//

    /**
     * @notice Check if an output has been proven.
     * @dev Helper function for accessing _provenOutput by hashing `output` through `_outputHash`.
     * @param orderId Order Id for help against output collisions.
     * @param outputDescription Output to examine
     */
    function _outputFilled(bytes32 orderId, OutputDescription calldata outputDescription) internal view returns (address solver, uint40 timestamp) {
        bytes32 outputHash = _outputHash(outputDescription);
        ProofStorage storage proofStorage = _provenOutput[orderId][outputDescription.remoteOracle][outputHash];
        (solver, timestamp) = (proofStorage.solver, proofStorage.timestamp);
        if (solver == address(0)) {
            // TODO: Check if there is an optimistic instance.
        }
    }

    /**
     * @notice Check if an output has been proven.
     * @dev Helper function for accessing _provenOutput by hashing `output` through `_outputHash`.
     * @param orderId Id of order containing the output.
     * @param outputDescription Output to search for.
     */
    function outputFilled(bytes32 orderId, OutputDescription calldata outputDescription) external view returns (address solver, uint40 timestamp) {
        return _outputFilled(orderId, outputDescription);
    }

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Function overload for outputFilled to allow proving multiple outputs in a single call.
     * Notice that the solver of the first provided output is reported as the entire intent solver.
     */
    function outputFilled(bytes32 orderId, OutputDescription[] calldata outputDescriptions) external view returns (address solver) {
        // Get the first solver. This is the solver we will report as whom that solved the intent.
        (solver, ) = _outputFilled(orderId, outputDescriptions[0]); // If outputDescriptions.length == 0 then this reverts.
        if (solver == address(0)) revert NotProven(orderId, outputDescriptions[0]);

        uint256 numOutputs = outputDescriptions.length;
        // Check that the rest of the outputs have been filled.
        // Notice that we discard the solver address and only check if it has been set
        for (uint256 i = 1; i < numOutputs; ++i) {
            (address outputSolver, ) = _outputFilled(orderId, outputDescriptions[i]);
            if (outputSolver == address(0)) revert NotProven(orderId, outputDescriptions[i]);
        }
        return solver;
    }

    // TODO: Try to simplify using function pointer to compare helpers.
    function outputFilledMaxTimestamp(bytes32 orderId, OutputDescription[] calldata outputDescriptions) external view returns (address solver, uint40 timestamp) {
        // Get the first solver. This is the solver we will report as whom that solved the intent.
        (solver, timestamp) = _outputFilled(orderId, outputDescriptions[0]); // If outputDescriptions.length == 0 then this reverts.
        if (solver == address(0)) revert NotProven(orderId, outputDescriptions[0]);

        uint256 numOutputs = outputDescriptions.length;
        // Check that the rest of the outputs have been filled.
        // Notice that we discard the solver address and only check if it has been set
        for (uint256 i = 1; i < numOutputs; ++i) {
            (address outputSolver, uint40 solvedAt) = _outputFilled(orderId, outputDescriptions[i]);
            if (solvedAt > timestamp) timestamp = solvedAt;
            if (outputSolver == address(0)) revert NotProven(orderId, outputDescriptions[i]);
        }
    }

    function outputFilledMinTimestamp(bytes32 orderId, OutputDescription[] calldata outputDescriptions) external view returns (address solver, uint40 timestamp) {
        // Get the first solver. This is the solver we will report as whom that solved the intent.
        (solver, timestamp) = _outputFilled(orderId, outputDescriptions[0]); // If outputDescriptions.length == 0 then this reverts.
        if (solver == address(0)) revert NotProven(orderId, outputDescriptions[0]);

        uint256 numOutputs = outputDescriptions.length;
        // Check that the rest of the outputs have been filled.
        // Notice that we discard the solver address and only check if it has been set
        for (uint256 i = 1; i < numOutputs; ++i) {
            (address outputSolver, uint40 solvedAt) = _outputFilled(orderId, outputDescriptions[i]);
            if (solvedAt < timestamp) timestamp = solvedAt;
            if (outputSolver == address(0)) revert NotProven(orderId, outputDescriptions[i]);
        }
    }

    // -- Optimistic Proving --//

    function optimistic(
        bytes32 orderId, bytes32 remoteOracle, uint8 orderType, bytes32 outputHash
    ) external {

    }

    /**
     * @notice Disputes a claim. If a claimed order hasn't been delivered post the fill deadline
     * then the order should be challenged. This allows anyone to attempt to claim the collateral
     * the filler provided (at the risk of losing their own collateral).
     * @dev For challengers it is important to properly verify transactions:
     * 1. Local oracle. If the local oracle isn't trusted, the filler may be able
     * to toggle between is verified and not. This makes it possible for the filler to steal
     * the challenger's collateral
     * 2. Remote Oracle. Likewise for the local oracle, remote oracles may be controllable by
     * the filler.
     */
    function dispute(
        bytes32 orderId, bytes32 remoteOracle, uint8 orderType, bytes32 outputHash
    ) external {
    }

    /**
     * @notice Finalise the dispute.
     */
    function completeDispute(
        bytes32 orderId, bytes32 remoteOracle, uint8 orderType, bytes32 outputHash
    ) external {
    }
}
