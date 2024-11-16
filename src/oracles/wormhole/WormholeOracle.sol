// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { WormholeVerifier } from "./external/callworm/WormholeVerifier.sol";
import { SmallStructs } from "./external/callworm/SmallStructs.sol";

import { IWormhole } from "./interfaces/IWormhole.sol";

import { CannotProveOrder, WrongChain } from "../../interfaces/Errors.sol";
import { OutputDescription } from "../../interfaces/Structs.sol";
import { BaseOracle } from "../BaseOracle.sol";

import "../OraclePayload.sol";

/**
 * @dev Oracles are also fillers
 */
abstract contract WormholeOracle is BaseOracle, IMessageEscrowStructs, WormholeVerifier {
    error NotApproved();
    error AlreadySet();
    error RemoteCallTooLarge();

    event MapMessagingProtocolIdentifierToChainId(bytes32 messagingProtocolIdentifier, uint32 chainId);

    /**
     * @notice Takes a messagingProtocolChainIdentifier and returns the expected (and configured)
     * block.chainId.
     * @dev This allows us to translate incoming messages from messaging protocols to easy to
     * understand chain ids that match the most coming identifier for chains. (their actual
     * identifier) rather than an arbitrary number that most messaging protocols use.
     */
    mapping(uint16 messagingProtocolChainIdentifier => uint32 blockChainId) _chainIdentifierToBlockChainId;
    mapping(uint32 blockChainId => uint16 messagingProtocolChainIdentifier) _blockChainIdToChainIdentifier;

    // For EVM it is generally set that 15 => Finality
    uint8 constant WORMHOLE_CONSISTENCY = 15;

    IWormhole public immutable WORMHOLE;

    constructor(address _wormhole) payable {
        WORMHOLE = IWormhole(_wormhole);
    }

    //-- View Functions --//

    function getChainIdentifierToBlockChainId(
        uint16 messagingProtocolChainIdentifier
    ) external view returns (uint32) {
        return _chainIdentifierToBlockChainId[messagingProtocolChainIdentifier];
    }

    function getBlockChainIdtoChainIdentifier(
        uint32 chainId
    ) external view returns (uint16) {
        return _blockChainIdToChainIdentifier[chainId];
    }

    //--- Sending Proofs & Generalised Incentives ---//

    /**
     * @notice Submits a proof the associated messaging protocol.
     * @dev Refunds excess value ot msg.sender. 
     * Does not check implement any check on the outputs.
     * It is expected that this proof will arrive at a supported oracle (destinationAddress)
     * and where the proof of fulfillment is needed.
     * fillDeadlines.length < outputs.length is checked but fillDeadlines.length > outputs.length is not.
     * Before calling this function ensure !(fillDeadlines.length > outputs.length).
     * @param outputs Outputs to prove. This function does not validate that these outputs are valid
     * or has been proven. When using this function, it is important to ensure that these outputs
     * are true AND these proofs were created by this (or the inheriting) contract.
     * @param fillDeadlines The fill times associated with the outputs. Used to match against the order.
     */
    function _submit(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillDeadlines
    ) internal {
        // This call fails if fillDeadlines.length < outputs.length
        bytes memory message = _encode(outputs, fillDeadlines);

        uint256 packageCost = WORMHOLE.messageFee();
        WORMHOLE.publishMessage{value: packageCost} (
            0,
            message,
            WORMHOLE_CONSISTENCY
        );

        // Refund excess value if any.
        if (msg.value > packageCost) {
            uint256 refund = msg.value - packageCost;
            SafeTransferLib.safeTransferETH(msg.sender, refund);
        }
    }

    /**
     * @notice Release a wormhole VAA.
     * @dev It is expected that this proof will arrive at a supported oracle (destinationAddress)
     * and where the proof of fulfillment is needed.
     * It is required that outputs.length == fillDeadlines.length. This is checked through 2 indirect checks of
     * not (fillDeadlines.length > outputs.length & fillDeadlines.length < outputs.length) => fillDeadlines.length ==
     * outputs.length.
     * @param outputs Outputs to prove. This function validates that the outputs has been correct set.
     * @param fillDeadlines The fill times associated with the outputs. Used to match against the order.
     */
    function submit(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillDeadlines
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
        // The submit call will fail if fillDeadlines.length < outputs.length.
        // This call also refunds excess value sent.
        _submit(outputs, fillDeadlines);
    }

    function receiveMessage(
        bytes calldata rawMessage
    ) external {
        (uint16 sourceIdentifier, bytes32 remoteOracle, bytes calldata message) = _verifyPacket(rawMessage);

        (OutputDescription[] memory outputs, uint32[] memory fillDeadlines) = _decode(message, remoteOracle);

        uint256 numOutputs = outputs.length;

        // Load the expected chainId (not the messaging protocol identifier).
        uint32 expectedBlockChainId = _chainIdentifierToBlockChainId[sourceIdentifier];
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
    }

    /** @dev _message is the entire Wormhole VAA. It contains both the proof & the message as a slice. */
    function _verifyPacket(bytes calldata _message) internal view returns(uint16 sourceIdentifier, bytes32 implementationIdentifier, bytes calldata message_) {

        // Decode & verify the VAA.
        // This uses the custom verification logic found in ./external/callworm/WormholeVerifier.sol.
        (
            SmallStructs.SmallVM memory vm,
            bytes calldata payload,
            bool valid,
            string memory reason
        ) = parseAndVerifyVM(_message);
        message_ = payload;

        // This is the preferred flow used by Wormhole.
        require(valid, reason);

        // Get the identifier for the source chain.
        sourceIdentifier = vm.emitterChainId;

        // Load the identifier for the calling contract.
        implementationIdentifier = vm.emitterAddress;

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
