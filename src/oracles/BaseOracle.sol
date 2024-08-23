// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { CannotProveOrder, FillDeadlineFarInFuture, FillDeadlineInPast, WrongChain } from "../interfaces/Errors.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { OrderKey, OutputDescription } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";

import "./OraclePayload.sol";

interface IIncentivizedMessageEscrowProofValidPeriod is IIncentivizedMessageEscrow {
    function proofValidPeriod(bytes32 destinationIdentifier) external view returns (uint64 duration);
}

/**
 * @dev Oracles are also fillers
 */
abstract contract BaseOracle is ICrossChainReceiver, IMessageEscrowStructs, IOracle {
    uint256 constant MAX_FUTURE_FILL_TIME = 7 days;

    uint32 public immutable CHAIN_ID;

    mapping(bytes32 outputHash => mapping(uint32 fillDeadline => mapping(bytes32 oracle => bool proven))) internal
        _provenOutput;

    IIncentivizedMessageEscrowProofValidPeriod public immutable escrow;

    error NotApprovedEscrow();

    constructor(address _escrow, uint32 chainId) {
        escrow = IIncentivizedMessageEscrowProofValidPeriod(_escrow);
        // For some reason GARP does not expose a chain id we can use :|
        CHAIN_ID = chainId;
    }

    /**
     * @notice Only allow the message escrow to call these functions
     */
    modifier onlyEscrow() {
        if (msg.sender != address(escrow)) revert NotApprovedEscrow();
        _;
    }

    /**
     * @notice Compute the hash of an output.
     */
    function _outputHash(OutputDescription calldata output) internal pure returns (bytes32 outputHash) {
        // Remember to not include (aka. exclude) remoteOracle & chainId
        outputHash = keccak256(bytes.concat(output.token, bytes32(output.amount), output.recipient, output.remoteCall));
    }

    /**
     * @notice Compute the hash of an output in memory.
     * @dev Is slightly more expensive than _outputHash. If possible, try to use _outputHash.
     */
    function _outputHashM(OutputDescription memory output) internal pure returns (bytes32 outputHash) {
        // Remember to not include (aka. exclude) remoteOracle & chainId
        outputHash = keccak256(bytes.concat(output.token, bytes32(output.amount), output.recipient, output.remoteCall));
    }

    /**
     * @notice Validates that fillDeadline honors the conditions:
     * - Fill time is not in the past (< currentTimestamp).
     * - Fill time is not too far in the future,
     * @param currentTimestamp Timestamp to compare filldeadline with. Is expected to be current time.
     * @param fillDeadline Timestamp to compare against currentTimestamp. Is timestamp that the conditions
     * will be checked for.
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

    // TODO: Is this function compatible with channels?
    // TODO: Is it better to just not check chainIds?
    function _validateChain(uint32 chainId) internal view {
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
        return _provenOutput[outputHash][fillDeadline][output.remoteOracle];
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
     * @dev Function overload for isProven that allows proving multiple outputs in a single call.
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

    //--- Sending Proofs & Generalised Incentives ---//

    //todo: onlyOwner
    function setRemoteImplementation(bytes32 chainIdentifier, bytes calldata implementation) external {
        escrow.setRemoteImplementation(chainIdentifier, implementation);
    }

    /**
     * @notice Submits a proof the associated messaging protocol.
     * @dev It is expected that this proof will arrive at a supported oracle (destinationAddress)
     * and where the proof of fulfillment is needed.
     * fillDeadlines.length < outputs.length is checked but fillDeadlines.length > outputs.length is not.
     * Before calling this function ensure !(fillDeadlines.length > outputs.length).
     * @param outputs Outputs to prove. This function does not validate that these outputs are valid
     * or has been proven. When using this function, it is important to ensure that these outputs
     * are true AND these proofs were created by this (or the inheriting) contract.
     * @param fillDeadlines The fill times associated with the outputs. Used to match against the order.
     * @param destinationIdentifier Chain id to send the order to. Is based on the messaging
     * protocol.
     * @param destinationAddress Oracle address on the destination.
     * @param incentive Generalised Incentives messaging incentive. Can be set very low if caller self-relays.
     */
    function _submit(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillDeadlines,
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        IncentiveDescription calldata incentive
    ) internal {
        // This call fails if fillDeadlines.length < outputs.length
        bytes memory message = _encode(outputs, fillDeadlines);

        // Read proofValidPeriod from the escrow. We will set this optimally for the caller.
        uint64 proofValidPeriod = escrow.proofValidPeriod(destinationIdentifier);
        unchecked {
            // Unchecked: timestamps doesn't overflow in uint64.
            uint64 deadline = proofValidPeriod == 0 ? 0 : uint64(block.timestamp) + proofValidPeriod;

            escrow.submitMessage{ value: msg.value }(
                destinationIdentifier, destinationAddress, message, incentive, deadline
            );
        }
    }

    /**
     * @notice Submits a proof the associated messaging protocol.
     * @dev It is expected that this proof will arrive at a supported oracle (destinationAddress)
     * and where the proof of fulfillment is needed.
     * It is required that outputs.length == fillDeadlines.length. This is checked through 2 indirect checks of
     * not (fillDeadlines.length > outputs.length & fillDeadlines.length < outputs.length) => fillDeadlines.length == outputs.length.
     * @param outputs Outputs to prove. This function validates that the outputs has been correct set.
     * @param fillDeadlines The fill times associated with the outputs. Used to match against the order.
     * @param destinationIdentifier Chain id to send the order to. Is based on the messaging
     * protocol.
     * @param destinationAddress Oracle address on the destination.
     * @param incentive Generalised Incentives messaging incentive. Can be set very low if caller self-relays.
     */
    function submit(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillDeadlines,
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        IncentiveDescription calldata incentive
    ) external payable {
        // The follow code chunk will fail if fillDeadlines.length > outputs.length.
        uint256 numFillDeadlines = fillDeadlines.length;
        unchecked {
            for (uint256 i; i < numFillDeadlines; ++i) {
                if (!_isProven(outputs[i], fillDeadlines[i])) {
                    revert CannotProveOrder();
                }
            }
        }
        // The submit call will fail if fillDeadlines.length < outputs.length
        _submit(outputs, fillDeadlines, destinationIdentifier, destinationAddress, incentive);
    }

    function receiveMessage(
        bytes32 sourceIdentifierbytes,
        bytes32, /* messageIdentifier */
        bytes calldata fromApplication,
        bytes calldata message
    ) external onlyEscrow returns (bytes memory acknowledgement) {
        // Do not use remoteOracle from decoded outputs.
        (OutputDescription[] memory outputs, uint32[] memory fillDeadlines) = _decode(message);

        // set the proof locally.
        uint256 numOutputs = outputs.length;

        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription memory output = outputs[i];
            // Check if sourceIdentifierbytes
            // TODO: unify chainIdentifiers. (types)
            if (uint32(uint256(sourceIdentifierbytes)) != output.chainId) {
                revert WrongChain(uint32(uint256(sourceIdentifierbytes)), output.chainId);
            }
            uint32 fillDeadline = fillDeadlines[i];
            bytes32 outputHash = _outputHashM(output);
            // even if fromApplication.length < 32 OR that generalised incentives always returns 32 byte length.
            _provenOutput[outputHash][fillDeadline][bytes32(fromApplication)] = true;
        }

        // We don't care about the ack.
        return hex"";
    }

    function receiveAck(
        bytes32 destinationIdentifier,
        bytes32 messageIdentifier,
        bytes calldata acknowledgement
    ) external onlyEscrow {
        // We don't do anything on ack.
    }

    //--- Message Encoding & Decoding ---//

    /**
     * @notice Encodes outputs and fillDeadlines into a bytearray that can be sent cross chain and cross implementations.
     * @dev This function reverts if fillDeadlines.length < outputs but not if fillDeadlines.length > outputs. Use with care.
     */
    function _encode(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillDeadlines
    ) internal pure returns (bytes memory encodedPayload) {
        uint256 numOutputs = outputs.length;
        encodedPayload = bytes.concat(bytes1(0x00), bytes2(uint16(numOutputs)));
        unchecked {
            for (uint256 i; i < numOutputs; ++i) {
                OutputDescription calldata output = outputs[i];
                // if fillDeadlines.length < outputs.length then fillDeadlines[i] will fail with out of index.
                uint32 fillDeadline = fillDeadlines[i];
                encodedPayload = bytes.concat(
                    encodedPayload,
                    output.remoteOracle,
                    output.token,
                    bytes32(output.amount),
                    output.recipient,
                    bytes4(output.chainId),
                    bytes4(fillDeadline),
                    bytes2(uint16(output.remoteCall.length)),
                    output.remoteCall
                );
            }
        }
    }

    /**
     * @notice Converts an encoded payload into decoded proof descriptions.
     * @dev Do not use remoteOracle from decoded outputs.
     * encodedPayload does not contain any "security". The payload will be "decoded by fire" as it is expected
     * to be encoded by _encode.
     * If a foreign contract can out anything here, it important to only attribute the decoded outputs as from that contract
     * to ensure the outputs does not poison other storage.
     * @param encodedPayload Payload that has been encoded with _encode. Will be decoded into outputs and fillDeadlines.
     * @return outputs Decoded outputs.
     * @return fillDeadlines Decoded fill times.
     */
    function _decode(bytes calldata encodedPayload)
        internal
        pure
        returns (OutputDescription[] memory outputs, uint32[] memory fillDeadlines)
    {
        unchecked {
            uint256 numOutputs = uint256(uint16(bytes2(encodedPayload[NUM_OUTPUTS_START:NUM_OUTPUTS_END])));

            outputs = new OutputDescription[](numOutputs);
            fillDeadlines = new uint32[](numOutputs);
            uint256 pointer = 0;
            for (uint256 outputIndex; outputIndex < numOutputs; ++outputIndex) {
                uint256 remoteCallLength =
                    uint16(bytes2(encodedPayload[pointer + REMOTE_CALL_LENGTH_START:pointer + REMOTE_CALL_LENGTH_END]));
                // TODO: can we optimise this decoding scheme? I think yes.
                outputs[outputIndex] = OutputDescription({
                    remoteOracle: bytes32(0), // Do not use this field.
                    token: bytes32(encodedPayload[pointer + OUTPUT_TOKEN_START:pointer + OUTPUT_TOKEN_END]),
                    amount: uint256(bytes32(encodedPayload[pointer + OUTPUT_AMOUNT_START:pointer + OUTPUT_AMOUNT_END])),
                    recipient: bytes32(encodedPayload[pointer + OUTPUT_RECIPIENT_START:pointer + OUTPUT_RECIPIENT_END]),
                    chainId: uint32(bytes4(encodedPayload[pointer + OUTPUT_CHAIN_ID_START:pointer + OUTPUT_CHAIN_ID_END])),
                    remoteCall: encodedPayload[pointer + REMOTE_CALL_START:pointer + REMOTE_CALL_START + remoteCallLength]
                });
                fillDeadlines[outputIndex] =
                    uint32(bytes4(encodedPayload[pointer + OUTPUT_FILL_DEADLINE_START:pointer + OUTPUT_FILL_DEADLINE_END]));

                pointer += OUTPUT_LENGTH + remoteCallLength;
            }
        }
    }
}
