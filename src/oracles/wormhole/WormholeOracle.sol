// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "solady/src/auth/Ownable.sol";

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { WormholeVerifier } from "./external/callworm/WormholeVerifier.sol";
import { SmallStructs } from "./external/callworm/SmallStructs.sol";

import { IWormhole } from "./interfaces/IWormhole.sol";

import { CannotProveOrder, WrongChain } from "../../interfaces/Errors.sol";
import { OutputDescription } from "../../libs/CatalystOrderType.sol";
import { BaseOracle } from "../BaseOracle.sol";

import { PayloadEncodingLibrary } from "../PayloadEncodingLibrary.sol";

import { IExtendedSimpleOracle } from "../../interfaces/IExtendedSimpleOracle.sol";

contract WormholeOracle is BaseOracle, IExtendedSimpleOracle, IMessageEscrowStructs, WormholeVerifier, Ownable {
    error AlreadySet();
    error RemoteCallTooLarge();
    error NotStored(uint256 index);

    event MapMessagingProtocolIdentifierToChainId(uint16 messagingProtocolIdentifier, uint32 chainId);

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

    constructor(address _owner, address _wormhole) payable WormholeVerifier(_wormhole) {
        _initializeOwner(_owner);
        WORMHOLE = IWormhole(_wormhole);
    }

    receive() external payable {
        // Lets us gets refunds from Wormhole.
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
     */
    function _submit(
        address caller,
        bytes[] calldata payloads
    ) internal returns (uint256 refund) {
        // This call fails if fillDeadlines.length < outputs.length
        bytes memory message = PayloadEncodingLibrary.encodeMessage(_getIdentifier(caller), payloads);

        uint256 packageCost = WORMHOLE.messageFee();
        WORMHOLE.publishMessage{value: packageCost} (
            0,
            message,
            WORMHOLE_CONSISTENCY
        );

        // Refund excess value if any.
        if (msg.value > packageCost) {
            refund = msg.value - packageCost;
            SafeTransferLib.safeTransferETH(msg.sender, refund);
        }
    }

    /** @notice Submits proofs directly to Wormhole. This does not store proofs in any way. */
    function submit(
        bytes[] calldata payloads
    ) public payable returns (uint256 refund) {
        return _submit(msg.sender, payloads);
    }

    /** @notice Submits proofs that have been stored in this oracle directly to Wormhole. */
    function submit(
        address proofSource,
        bytes[] calldata payloads
    ) public payable returns (uint256 refund) {
        // Check if each payload has been stored here.
        uint256 numPayloads = payloads.length;
        for (uint256 i; i < numPayloads; ++i) {
            if (!_attestations[bytes32(0)][bytes32(uint256(uint160(proofSource)))][keccak256(payloads[i])]) revert NotStored(i);
        }
        // Payloads are good. We can submit them onbehalf of proofSource.
        return _submit(proofSource, payloads);
    }

    function submitAndStore(
        bytes[] calldata payloads
    ) public payable returns (uint256 refund) {
        uint256 numPayloads = payloads.length;
        for (uint256 i; i < numPayloads; ++i) {
            storeProof(keccak256(payloads[i]));
        }
        return _submit(msg.sender, payloads);
    }

    function receiveMessage(
        bytes calldata rawMessage
    ) external {
        (uint16 remoteChainIdentifier, bytes32 remoteSenderIdentifier, bytes calldata message) = _verifyPacket(rawMessage);
        (bytes32 identifierFromMessage, bytes32[] memory payloadHashes) = PayloadEncodingLibrary.decodeMessage(message);

        // Construct the identifier
        bytes32 senderIdentifier = _enhanceIdentifier(remoteSenderIdentifier, identifierFromMessage);

        // TODO: map remoteChainIdentifier to canonical chain id instead of messaging protocol specific.

        // Store payload attestations;
        uint256 numPayloads = payloadHashes.length;
        for (uint256 i; i < numPayloads; ++i) {
            _attestations[bytes32(uint256(remoteChainIdentifier))][senderIdentifier][payloadHashes[i]] = true;

            // TODO: emit OutputProven(fillDeadline, outputHash);
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
}
