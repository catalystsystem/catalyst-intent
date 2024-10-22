// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "solady/src/auth/Ownable.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { CannotProveOrder, WrongChain } from "../../interfaces/Errors.sol";
import { OutputDescription } from "../../interfaces/Structs.sol";
import { BaseOracle } from "../BaseOracle.sol";

import "./OraclePayload.sol";

interface IIncentivizedMessageEscrowProofValidPeriod is IIncentivizedMessageEscrow {
    function proofValidPeriod(
        bytes32 destinationIdentifier
    ) external view returns (uint64 duration);
}

/**
 * @dev Oracles are also fillers
 */
abstract contract GeneralisedIncentivesOracle is BaseOracle, ICrossChainReceiver, IMessageEscrowStructs, Ownable {
    error NotApproved();
    error RemoteCallTooLarge();

    event MapMessagingProtocolIdentifierToChainId(bytes32 messagingProtocolIdentifier, uint32 chainId);

    /**
     * @notice Only allow the message escrow to call these functions
     */
    modifier onlyEscrow() {
        if (msg.sender != address(escrow)) revert NotApproved();
        _;
    }

    IIncentivizedMessageEscrowProofValidPeriod public immutable escrow;

    constructor(address _owner, address _escrow) payable {
        _initializeOwner(_owner);
        escrow = IIncentivizedMessageEscrowProofValidPeriod(_escrow);
    }

    //--- Sending Proofs & Generalised Incentives ---//

    /**
     * @notice Defines the remote messaging protocol.
     * @dev Can only be called once for each chain.
     */
    function setRemoteImplementation(
        bytes32 chainIdentifier,
        uint32 blockChainIdOfChainIdentifier,
        bytes calldata implementation
    ) external onlyOwner {
        //  escrow.setRemoteImplementation does not allow calling multiple times.
        escrow.setRemoteImplementation(chainIdentifier, implementation);

        _chainIdentifierToBlockChainId[chainIdentifier] = blockChainIdOfChainIdentifier;
        emit MapMessagingProtocolIdentifierToChainId(chainIdentifier, blockChainIdOfChainIdentifier);
    }

    /**
     * @notice Submits a proof the associated messaging protocol.
     * @dev Does not check implement any check on the outputs.
     * It is expected that this proof will arrive at a supported oracle (destinationAddress)
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
     * not (fillDeadlines.length > outputs.length & fillDeadlines.length < outputs.length) => fillDeadlines.length ==
     * outputs.length.
     * @param outputs Outputs to prove. This function validates that the outputs has been correct set.
     * @param fillDeadlines The fill times associated with the outputs. Used to match against the order.
     * @param destinationIdentifier Messaging protocol's chain identifier to send the order to. Is not the same as
     * chainId.
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
                OutputDescription calldata output = outputs[i];
                // The chainId of the output has to match this chain. This is required to ensure that it originated
                // here.
                _validateChain(output.chainId);
                _validateRemoteOracleAddress(output.remoteOracle);
                // Validate that we have proofs for each output.
                if (!_isProven(output, fillDeadlines[i])) {
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
        // Length of fromApplication is 65 bytes. We need the last 32 bytes.
        bytes32 remoteOracle = bytes32(fromApplication[65 - 32:]);
        (OutputDescription[] memory outputs, uint32[] memory fillDeadlines) = _decode(message, remoteOracle);

        // set the proof locally.
        uint256 numOutputs = outputs.length;

        // Load the expected chainId (not the messaging protocol identifier).
        uint32 expectedBlockChainId = _chainIdentifierToBlockChainId[sourceIdentifierbytes];
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription memory output = outputs[i];
            // Check if sourceIdentifierbytes matches the output.
            if (expectedBlockChainId != output.chainId) {
                revert WrongChain(expectedBlockChainId, output.chainId);
            }
            uint32 fillDeadline = fillDeadlines[i];
            bytes32 outputHash = _outputHashM(output);
            _provenOutput[outputHash][fillDeadline] = true;

            emit OutputProven(fillDeadline, outputHash);
        }

        // We don't care about the ack.
        return hex"";
    }

    function receiveAck(
        bytes32, /* destinationIdentifier */
        bytes32, /* messageIdentifier */
        bytes calldata /* acknowledgement */
    ) external onlyEscrow {
        // We don't do anything on ack.
    }

    //--- Message Encoding & Decoding ---//

    /**
     * @notice Encodes outputs and fillDeadlines into a bytearray to be sent cross chain.
     * @dev This function reverts if fillDeadlines.length < outputs but not if fillDeadlines.length > outputs.
     * Use with care.
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
                // Check output remoteCall length.
                if (output.remoteCall.length > type(uint16).max) revert RemoteCallTooLarge();
                encodedPayload = bytes.concat(
                    encodedPayload,
                    output.token,
                    bytes32(output.amount),
                    output.recipient,
                    bytes4(output.chainId),
                    bytes4(fillDeadline),
                    bytes2(uint16(output.remoteCall.length)), // this cannot overflow since length is checked to be less than max.
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
     * If a foreign contract set anything here, it important to only attribute the decoded outputs to that contract
     * to ensure the outputs does not poison other storage. If someone trusts that oracle, it is their problem.
     * @param encodedPayload Payload that has been encoded with _encode. Will be decoded into outputs and fillDeadlines.
     * @return outputs Decoded outputs.
     * @return fillDeadlines Decoded fill times.
     */
    function _decode(
        bytes calldata encodedPayload,
        bytes32 remoteOracle
    ) internal pure returns (OutputDescription[] memory outputs, uint32[] memory fillDeadlines) {
        unchecked {
            uint256 numOutputs = uint256(uint16(bytes2(encodedPayload[NUM_OUTPUTS_START:NUM_OUTPUTS_END])));

            outputs = new OutputDescription[](numOutputs);
            fillDeadlines = new uint32[](numOutputs);
            uint256 pointer = OUTPUT_TOKEN_START;
            for (uint256 outputIndex; outputIndex < numOutputs; ++outputIndex) {
                bytes32 token = bytes32(encodedPayload[pointer:pointer += (OUTPUT_TOKEN_END - OUTPUT_TOKEN_START)]);
                uint256 amount =
                    uint256(bytes32(encodedPayload[pointer:pointer += (OUTPUT_AMOUNT_END - OUTPUT_AMOUNT_START)]));
                bytes32 recipient =
                    bytes32(encodedPayload[pointer:pointer += (OUTPUT_RECIPIENT_END - OUTPUT_RECIPIENT_START)]);
                uint32 chainId =
                    uint32(bytes4(encodedPayload[pointer:pointer += (OUTPUT_CHAIN_ID_END - OUTPUT_CHAIN_ID_START)]));
                fillDeadlines[outputIndex] = uint32(
                    bytes4(encodedPayload[pointer:pointer += (OUTPUT_FILL_DEADLINE_END - OUTPUT_FILL_DEADLINE_START)])
                );
                uint256 remoteCallLength = uint16(
                    bytes2(encodedPayload[pointer:pointer += (REMOTE_CALL_LENGTH_END - REMOTE_CALL_LENGTH_START)])
                );

                outputs[outputIndex] = OutputDescription({
                    remoteOracle: remoteOracle,
                    token: token,
                    amount: amount,
                    recipient: recipient,
                    chainId: chainId,
                    remoteCall: encodedPayload[pointer:pointer += remoteCallLength]
                });
            }
        }
    }
}
