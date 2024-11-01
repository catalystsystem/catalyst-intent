// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { FillDeadlineFarInFuture, FillDeadlineInPast, WrongChain, WrongRemoteOracle } from "../interfaces/Errors.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { OrderKey, OutputDescription } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";

/**
 * @dev Oracles are also fillers
 */
abstract contract BaseOracle is IOracle {

    event OutputProven(uint32 fillDeadline, bytes32 outputHash);

    uint256 constant MAX_FUTURE_FILL_TIME = 3 days;

    /**
     * @notice We use the chain's canonical id rather than the messaging protocol id for clarity.
     */
    uint32 public immutable CHAIN_ID = uint32(block.chainid);
    bytes32 immutable ADDRESS_THIS = bytes32(uint256(uint160(address(this))));

    mapping(bytes32 outputHash => mapping(uint32 fillDeadline => bool proven)) internal _provenOutput;

    //-- Helpers --//

    /**
     * @notice Validate that the remote oracle address is this oracle.
     * @dev For some oracles, it might be required that you "cheat" and change the encoding here.
     * Don't worry (or do worry) because the other side loads the payload as bytes32(bytes).
     */
    function _validateRemoteOracleAddress(
        bytes32 remoteOracle
    ) internal view virtual {
        if (ADDRESS_THIS != remoteOracle) revert WrongRemoteOracle(ADDRESS_THIS, remoteOracle);
    }

    /**
     * @notice Compute the hash for an output. This allows us more easily identify it.
     */
    function _outputHash(
        OutputDescription calldata output
    ) internal pure returns (bytes32 outputHash) {
        outputHash = keccak256(
            bytes.concat(
                output.remoteOracle,
                output.token,
                bytes4(output.chainId),
                bytes32(output.amount),
                output.recipient,
                output.remoteCall
            )
        );
    }

    /**
     * @notice Compute the hash of an output in memory.
     * @dev Is slightly more expensive than _outputHash. If possible, try to use _outputHash.
     */
    function _outputHashM(
        OutputDescription memory output
    ) internal pure returns (bytes32 outputHash) {
        outputHash = keccak256(
            bytes.concat(
                output.remoteOracle,
                output.token,
                bytes4(output.chainId),
                bytes32(output.amount),
                output.recipient,
                output.remoteCall
            )
        );
    }

    /**
     * @notice Validates that fillDeadline honors the conditions:
     * - Fill time is not in the past (< paymentTimestamp).
     * - Fill time is not too far in the future,
     * @param currentTimestamp Timestamp to compare fillDeadline against.
     * Is expected to be the time when the payment was recorded.
     * @param fillDeadline Timestamp to compare against paymentTimestamp.
     * The conditions will be checked against this timestamp.
     */
    function _validateTimestamp(uint32 currentTimestamp, uint32 fillDeadline) internal pure {
        unchecked {
            // FillDeadline may not be in the past.
            if (fillDeadline < currentTimestamp) revert FillDeadlineInPast();
            // Check that fillDeadline isn't far in the future.
            // The idea is to protect users against random transfers through this contract.
            // unchecked: type(uint32).max * 2 < type(uint256).max
            if (uint256(fillDeadline) > uint256(currentTimestamp) + uint256(MAX_FUTURE_FILL_TIME)) {
                revert FillDeadlineFarInFuture();
            }
        }
    }

    /**
     * @notice Validate that expected chain (@param chainId) matches this chain's chainId (block.chainId)
     */
    function _validateChain(
        uint32 chainId
    ) internal view {
        if (CHAIN_ID != chainId) revert WrongChain(CHAIN_ID, chainId);
    }

    //--- Output Proofs ---/

    /**
     * @notice Check if an output has been proven.
     * @dev Helper function for accessing _provenOutput by hashing `output` through `_outputHash`.
     * @param output Output to check for.
     * @param fillDeadline The expected fill time. Is used as a time & collision check.
     */
    function _isProven(OutputDescription calldata output, uint32 fillDeadline) internal view returns (bool proven) {
        bytes32 outputHash = _outputHash(output);
        return _provenOutput[outputHash][fillDeadline];
    }

    /**
     * @notice Check if an output has been proven.
     * @dev Helper function for accessing _provenOutput by hashing `output` through `_outputHash`.
     * @param output Output to check for.
     * @param fillDeadline The expected fill time. Is used as a time & collision check.
     */
    function isProven(OutputDescription calldata output, uint32 fillDeadline) external view returns (bool proven) {
        return _isProven(output, fillDeadline);
    }

    /**
     * @dev Function overload for isProven to allow proving multiple outputs in a single call.
     */
    function isProven(OutputDescription[] calldata outputs, uint32 fillDeadline) public view returns (bool proven) {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            if (!_isProven(outputs[i], fillDeadline)) {
                return proven = false;
            }
        }
        return proven = true;
    }
}
