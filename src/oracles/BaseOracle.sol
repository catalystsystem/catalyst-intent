// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { CannotProveOrder, FillTimeFarInFuture, FillTimeInPast, WrongChain } from "../interfaces/Errors.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { OrderKey, OutputDescription } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";

import "./OraclePayload.sol";

interface IIncentivizedMessageEscrowProofValidPeriod is IIncentivizedMessageEscrow {
    function proofValidPeriod(bytes32 destinationIdentifier) external view returns(uint64 duration);
}

/**
 * @dev Oracles are also fillers
 */
abstract contract BaseOracle is ICrossChainReceiver, IMessageEscrowStructs, IOracle {
    uint256 constant MAX_FUTURE_FILL_TIME = 7 days;

    mapping(bytes32 outputHash => mapping(uint32 fillTime => mapping(bytes32 oracle => bool proven))) internal
        _provenOutput;

    IIncentivizedMessageEscrowProofValidPeriod public immutable escrow;

    error NotApprovedEscrow();

    constructor(address _escrow) {
        escrow = IIncentivizedMessageEscrowProofValidPeriod(_escrow);
    }

    /** @notice Only allow the message escrow to call these functions */
    modifier onlyEscrow() {
        if (msg.sender != address(escrow)) revert NotApprovedEscrow();
        _;
    }

    /**
     * @notice Compute hash an output.
     */
    function _outputHash(OutputDescription calldata output) internal pure returns (bytes32 outputHash) {
        // TODO: handwrap with manually exclude remoteOracle
        outputHash = keccak256(bytes.concat(abi.encode(output))); // TODO: Efficiency? // TODO: hash with orderKeyHash for collision?
    }

    /**
     * @notice Compute hash an output while output is in memory.
     * @dev Is slightly more expensive than _outputHash. If possible, try to use _outputHash.
     */
    function _outputHashM(OutputDescription memory output) internal pure returns (bytes32 outputHash) {
        // TODO: handwrap with manually exclude remoteOracle
        outputHash = keccak256(bytes.concat(abi.encode(output))); // TODO: Efficiency? // TODO: hash with orderKeyHash for collision?
    }

    /**
     * @notice Validates that fillTime honors the conditions:
     * - Fill time is not in the past (< currentTimestamp).
     * - Fill time is not too far in the future,
     * @param currentTimestamp Timestamp to compare filltime with. Is expected to be current time.
     * @param fillTime Timestamp to compare against currentTimestamp. Is timestamp that the conditions
     * will be checked for.
     */
    function _validateTimestamp(uint32 currentTimestamp, uint32 fillTime) internal pure {
        unchecked {
            // FillTime may not be in the past.
            if (fillTime < currentTimestamp) revert FillTimeInPast();
            // Check that fillTime isn't far in the future.
            // The idea is to protect users against random transfers through this contract.
            // unchecked: type(uint32).max * 2 < type(uint256).max
            if (uint256(fillTime) > uint256(currentTimestamp) + uint256(MAX_FUTURE_FILL_TIME)) revert FillTimeFarInFuture();
        }
    }


    //--- Output Proofs ---/

    /**
     * @notice Check if an output has been proven.
     * @dev Helper function for accessing _provenOutput by hashing `output` through `_outputHash`.
     * @param output Output to check for.
     * @param fillTime The expected fill time. Is used as a time & collision check.
     */
    function _isProven(OutputDescription calldata output, uint32 fillTime) internal view returns (bool proven) {
        bytes32 outputHash = _outputHash(output);
        return _provenOutput[outputHash][fillTime][output.remoteOracle];
    }

    /**
     * @notice Check if an output has been proven.
     * @dev Helper function for accessing _provenOutput by hashing `output` through `_outputHash`.
     * @param output Output to check for.
     * @param fillTime The expected fill time. Is used as a time & collision check.
     */
    function isProven(OutputDescription calldata output, uint32 fillTime) external view returns (bool proven) {
        return _isProven(output, fillTime);
    }

    /** @dev Function overload for isProven that allows proving multiple outputs in a single call. */
    function isProven(OutputDescription[] calldata outputs, uint32 fillTime) public view returns (bool proven) {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            if (!_isProven(outputs[i], fillTime)) {
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
     * fillTimes.length < outputs.length is checked but fillTimes.length > outputs.length is not.
     * Before calling this function ensure !(fillTimes.length > outputs.length).
     * @param outputs Outputs to prove. This function does not validate that these outputs are valid
     * or has been proven. When using this function, it is important to ensure that these outputs
     * are true AND these proofs were created by this (or the inheriting) contract.
     * @param fillTimes The fill times associated with the outputs. Used to match against the order.
     * @param destinationIdentifier Chain id to send the order to. Is based on the messaging
     * protocol.
     * @param destinationAddress Oracle address on the destination. 
     * @param incentive Generalised Incentives messaging incentive. Can be set very low if caller self-relays.
     */
    function _submit(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillTimes,
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        IncentiveDescription calldata incentive
    ) internal {
        // This call fails if fillTimes.length < outputs.length
        bytes memory message = _encode(outputs, fillTimes);

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
     * It is required that outputs.length == fillTimes.length. This is checked through 2 indirect checks of
     * not (fillTimes.length > outputs.length & fillTimes.length < outputs.length) => fillTimes.length == outputs.length.
     * @param outputs Outputs to prove. This function validates that the outputs has been correct set.
     * @param fillTimes The fill times associated with the outputs. Used to match against the order.
     * @param destinationIdentifier Chain id to send the order to. Is based on the messaging
     * protocol.
     * @param destinationAddress Oracle address on the destination. 
     * @param incentive Generalised Incentives messaging incentive. Can be set very low if caller self-relays.
     */
    function submit(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillTimes,
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        IncentiveDescription calldata incentive
    ) external payable {
        // The follow code chunk will fail if fillTimes.length > outputs.length.
        uint256 numFillTimes = fillTimes.length;
        unchecked {
            for (uint256 i; i < numFillTimes; ++i) {
                if (!_isProven(outputs[i], fillTimes[i])) {
                    revert CannotProveOrder();
                }
            }
        }
        // The submit call will fail if fillTimes.length < outputs.length
        _submit(outputs, fillTimes, destinationIdentifier, destinationAddress, incentive);
    }

    function receiveMessage(
        bytes32 sourceIdentifierbytes,
        bytes32, /* messageIdentifier */
        bytes calldata fromApplication,
        bytes calldata message
    ) external onlyEscrow returns (bytes memory acknowledgement) {
        (OutputDescription[] memory outputs, uint32[] memory fillTimes) = _decode(message);

        // set the proof locally.
        uint256 numOutputs = outputs.length;

        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription memory output = outputs[i];
            // Check if sourceIdentifierbytes
            // TODO: unify chainIdentifiers. (types)
            if (uint32(uint256(sourceIdentifierbytes)) != output.chainId) revert WrongChain();
            uint32 fillTime = fillTimes[i];
            bytes32 outputHash = _outputHashM(output);
            // TODO: Test that bytes32(fromApplication) right shifts fromApplication (0x0000...address)
            // even if fromApplication.length < 32 OR that generalised incentives always returns 32 byte length.
            _provenOutput[outputHash][fillTime][bytes32(fromApplication)] = true;
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
     * @notice Encodes outputs and fillTimes into a bytearray that can be sent cross chain and cross implementations.
     * @dev This function reverts if fillTimes.length < outputs but not if fillTimes.length > outputs. Use with care.
     */
    function _encode(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillTimes
    ) internal pure returns (bytes memory encodedPayload) {
        uint256 numOutputs = outputs.length;
        encodedPayload = bytes.concat(EXECUTE_PROOFS, bytes2(uint16(numOutputs)));
        unchecked {
            for (uint256 i; i < numOutputs; ++i) {
                OutputDescription calldata output = outputs[i];
                // if fillTimes.length < outputs.length then fillTimes[i] will fail with out of index.
                uint32 fillTime = fillTimes[i];
                encodedPayload = bytes.concat(
                    encodedPayload,
                    output.token,
                    bytes32(output.amount),
                    output.recipient,
                    bytes32(uint256(output.chainId)),
                    bytes4(fillTime)
                );
            }
        }
    }

    /**
     * @notice Converts an encoded payload into decoded proof descriptions.
     * @dev encodedPayload does not contain any "security". The payload will be "decoded by fire" as it is expected
     * to be encoded by _encode.
     * If a foreign contract can out anything here, it important to only attribute the decoded outputs as from that contract
     * to ensure the outputs does not poison other storage.
     * @param encodedPayload Payload that has been encoded with _encode. Will be decoded into outputs and fillTimes.
     * @return outputs Decoded outputs.
     * @return fillTimes Decoded fill times.
     */
    function _decode(bytes calldata encodedPayload)
        internal
        pure
        returns (OutputDescription[] memory outputs, uint32[] memory fillTimes)
    {
        unchecked {
            uint256 numOutputs = uint256(uint16(bytes2(encodedPayload[NUM_OUTPUTS_START:NUM_OUTPUTS_END])));

            outputs = new OutputDescription[](numOutputs);
            fillTimes = new uint32[](numOutputs);
            uint256 pointer = 0;
            for (uint256 outputIndex; outputIndex < numOutputs; ++outputIndex) {
                outputs[outputIndex] = OutputDescription({
                    token: bytes32(encodedPayload[pointer + OUTPUT_TOKEN_START:pointer + OUTPUT_TOKEN_END]),
                    amount: uint256(bytes32(encodedPayload[pointer + OUTPUT_AMOUNT_START:pointer + OUTPUT_AMOUNT_END])),
                    recipient: bytes32(encodedPayload[pointer + OUTPUT_RECIPIENT_START:pointer + OUTPUT_RECIPIENT_END]),
                    chainId: uint32(
                        uint256(bytes32(encodedPayload[pointer + OUTPUT_CHAIN_ID_START:pointer + OUTPUT_CHAIN_ID_END]))
                    ),
                    // TODO:
                    remoteOracle: bytes32(0),
                    remoteCall: hex""
                });
                fillTimes[outputIndex] =
                    uint32(bytes4(encodedPayload[pointer + OUTPUT_FILLTIME_START:pointer + OUTPUT_FILLTIME_END]));
                pointer += OUTPUT_LENGTH;
            }
        }
    }
}
