// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "solady/src/auth/Ownable.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import {
    CannotProveOrder,
    FillDeadlineFarInFuture,
    FillDeadlineInPast,
    WrongChain,
    WrongRemoteOracle
} from "../interfaces/Errors.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { OrderKey, OutputDescription } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";

import "./OraclePayload.sol";

interface IIncentivizedMessageEscrowProofValidPeriod is IIncentivizedMessageEscrow {
    function proofValidPeriod(
        bytes32 destinationIdentifier
    ) external view returns (uint64 duration);
}

/**
 * @dev Oracles are also fillers
 */
abstract contract BaseOracle is Ownable, ICrossChainReceiver, IMessageEscrowStructs, IOracle {
    error NotApproved();

    event OutputProven(uint32 fillDeadline, bytes32 outputHash);

    event MapMessagingProtocolIdentifierToChainId(bytes32 messagingProtocolIdentifier, uint32 chainId);

    uint256 constant MAX_FUTURE_FILL_TIME = 3 days;

    /**
     * @notice We use the chain's canonical id rather than the messaging protocol id for clarity.
     */
    uint32 public immutable CHAIN_ID = uint32(block.chainid);
    bytes32 immutable ADDRESS_THIS = bytes32(uint256(uint160(address(this))));

    /**
     * @notice Takes a messagingProtocolChainIdentifier and returns the expected (and configured)
     * block.chainId.
     * @dev This allows us to translate incoming messages from messaging protocols to easy to
     * understand chain ids that match the most coming identifier for chains. (their actual
     * identifier) rather than an arbitrary number that most messaging protocols use.
     */
    mapping(bytes32 messagingProtocolChainIdentifier => uint32 blockChainId) _chainIdentifierToBlockChainId;

    mapping(bytes32 outputHash => mapping(uint32 fillDeadline => bool proven)) internal _provenOutput;

    IIncentivizedMessageEscrowProofValidPeriod public immutable escrow;

    constructor(address _owner, address _escrow) {
        _initializeOwner(_owner);
        escrow = IIncentivizedMessageEscrowProofValidPeriod(_escrow);
    }

    //-- View Functions --//

    function getChainIdentifierToBlockChainId(
        bytes32 messagingProtocolChainIdentifier
    ) external view returns (uint32) {
        return _chainIdentifierToBlockChainId[messagingProtocolChainIdentifier];
    }

    //-- Helpers --//
    /**
     * @notice Only allow the message escrow to call these functions
     */
    modifier onlyEscrow() {
        if (msg.sender != address(escrow)) revert NotApproved();
        _;
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
                encodedPayload = bytes.concat(
                    encodedPayload,
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
