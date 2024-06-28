// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { FillTimeFarInFuture, FillTimeInPast, WrongChain } from "../interfaces/Errors.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { Output } from "../interfaces/ISettlementContract.sol";
import { OrderKey } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";

import "./OraclePayload.sol";

/**
 * @dev Oracles are also fillers
 */
abstract contract BaseOracle is ICrossChainReceiver, IMessageEscrowStructs, IOracle {
    uint256 constant MAX_FUTURE_FILL_TIME = 7 days;

    mapping(bytes32 outputHash => mapping(uint32 fillTime => mapping(bytes32 oracle => bool proven))) internal
        _provenOutput;

    IIncentivizedMessageEscrow public immutable escrow;

    error NotApprovedEscrow();

    constructor(address _escrow) {
        // Solution 1: Set the escrow.
        escrow = IIncentivizedMessageEscrow(_escrow);
    }

    modifier onlyEscrow() {
        if (msg.sender != address(escrow)) revert NotApprovedEscrow();
        _;
    }

    function _isProven(Output calldata output, uint32 fillTime, bytes32 oracle) internal view returns (bool proven) {
        bytes32 outputHash = _outputHash(output, bytes32(0));
        return _provenOutput[outputHash][fillTime][oracle];
    }

    function isProven(Output calldata output, uint32 fillTime, bytes32 oracle) external view returns (bool proven) {
        return _isProven(output, fillTime, oracle);
    }

    function isProven(Output[] calldata outputs, uint32 fillTime, bytes32 oracle) public view returns (bool proven) {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            if (!_isProven(outputs[i], fillTime, oracle)) {
                return proven = false;
            }
        }
        return proven = true;
    }

    /**
     * TODO: define an output salt which is some value (time + nonce?) that allows us to
     * discriminate between different outputs in time & space.
     */
    function _outputHash(Output calldata output, bytes32 outputSalt) internal pure returns (bytes32) {
        return keccak256(bytes.concat(abi.encode(output), outputSalt)); // TODO: Efficiency? // TODO: hash with orderKeyHash for collision?
    }

    function _outputHashM(Output memory output, bytes32 outputSalt) internal pure returns (bytes32) {
        return keccak256(bytes.concat(abi.encode(output), outputSalt)); // TODO: Efficiency? // TODO: hash with orderKeyHash for collision?
    }

    function _validateTimestamp(uint32 timestamp, uint32 fillTime) internal pure {
        // FillTime may not be in the past.
        if (fillTime < timestamp) revert FillTimeInPast();
        // Check that fillTime isn't far in the future.
        // The idea is to protect users against random transfers through this contract.
        if (fillTime > timestamp + MAX_FUTURE_FILL_TIME) revert FillTimeFarInFuture();
    }

    //--- Sending Proofs & Generalised Incentives ---//

    // TODO: figure out what the best best interface for this function is
    function _submit(
        Output[] calldata outputs,
        uint32[] calldata fillTimes,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) internal {
        // TODO: Figure out a better idea than abi.encode
        bytes memory message = _encode(outputs, fillTimes);
        // Deadline is set to 0.
        escrow.submitMessage(destinationIdentifier, destinationAddress, message, incentive, deadline);
    }

    function receiveMessage(
        bytes32 sourceIdentifierbytes,
        bytes32, /* messageIdentifier */
        bytes calldata fromApplication,
        bytes calldata message
    ) external onlyEscrow returns (bytes memory acknowledgement) {
        (Output[] memory outputs, uint32[] memory fillTimes) = _decode(message);

        // set the proof locally.
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            Output memory output = outputs[i];
            // Check if sourceIdentifierbytes
            // TODO: unify chainIdentifiers. (types)
            if (uint32(uint256(sourceIdentifierbytes)) != output.chainId) revert WrongChain();
            uint32 fillTime = fillTimes[i];
            bytes32 outputHash = _outputHashM(output, bytes32(0)); // TODO: salt
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
        // We don't actually do anything on ack.
    }

    //--- Message Encoding & Decoding ---//

    /**
     * @notice Encodes outputs and fillTimes into a bytearray that can be sent cross-implementations.
     * @dev This function does not check if fillTimes.length > outputs. Use with care.
     * This function will revert if fillTimes.length < outputs.
     */
    function _encode(
        Output[] calldata outputs,
        uint32[] calldata fillTimes
    ) internal pure returns (bytes memory encodedPayload) {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            Output calldata output = outputs[i];
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

    /**
     * @notice Converts an encoded payload into a decoded list of structs.
     * @param encodedPayload Encoded payload to decode.
     * @return outputs Decoded outputs
     * @return fillTimes Decoded fill times.
     */
    function _decode(bytes calldata encodedPayload)
        internal
        pure
        returns (Output[] memory outputs, uint32[] memory fillTimes)
    {
        unchecked {
            uint256 numOutputs = uint256(uint16(bytes2(encodedPayload[NUM_OUTPUTS_START:NUM_OUTPUTS_END])));
            outputs = new Output[](numOutputs);
            fillTimes = new uint32[](numOutputs);
            uint256 pointer = 0;
            for (uint256 outputIndex; outputIndex < numOutputs; ++outputIndex) {
                outputs[outputIndex] = Output({
                    token: bytes32(encodedPayload[pointer + OUTPUT_TOKEN_START:pointer + OUTPUT_TOKEN_END]),
                    amount: uint256(bytes32(encodedPayload[pointer + OUTPUT_AMOUNT_START:pointer + OUTPUT_AMOUNT_END])),
                    recipient: bytes32(encodedPayload[pointer + OUTPUT_RECIPIENT_START:pointer + OUTPUT_RECIPIENT_END]),
                    chainId: uint32(
                        uint256(bytes32(encodedPayload[pointer + OUTPUT_CHAIN_ID_START:pointer + OUTPUT_CHAIN_ID_END]))
                    )
                });
                fillTimes[outputIndex] =
                    uint32(bytes4(encodedPayload[pointer + OUTPUT_FILLTIME_START:pointer + OUTPUT_FILLTIME_END]));
                pointer += OUTPUT_LENGTH;
            }
        }
    }
}
