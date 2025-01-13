// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "solady/auth/Ownable.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { WormholeVerifier } from "./external/callworm/WormholeVerifier.sol";
import { SmallStructs } from "./external/callworm/SmallStructs.sol";

import { IWormhole } from "./interfaces/IWormhole.sol";

import { CannotProveOrder, WrongChain } from "../../interfaces/Errors.sol";
import { OutputDescription } from "../../reactors/CatalystOrderType.sol";
import { BaseOracle } from "../BaseOracle.sol";

import { PayloadEncodingLibrary } from "../PayloadEncodingLibrary.sol";
import { IdentifierLib } from "../../libs/IdentifierLib.sol";

import { IPayloadCreator } from "../../interfaces/IPayloadCreator.sol";

contract WormholeOracle is BaseOracle, WormholeVerifier, Ownable {
    error AlreadySet();
    error RemoteCallTooLarge();
    error NotStored(uint256 index);
    error NotAllPayloadsValid();
    error ZeroValue();
    error NonZeroValue();

    event OutputProven(uint256 chainid, bytes32 remoteIdentifier, bytes32 payloadHash);
    event MapMessagingProtocolIdentifierToChainId(uint16 messagingProtocolIdentifier, uint256 chainId);

    /**
     * @notice Takes a messagingProtocolChainIdentifier and returns the expected (and configured)
     * block.chainId.
     * @dev This allows us to translate incoming messages from messaging protocols to easy to
     * understand chain ids that match the most coming identifier for chains. (their actual
     * identifier) rather than an arbitrary number that most messaging protocols use.
     */
    mapping(uint16 messagingProtocolChainIdentifier => uint256 blockChainId) _chainIdentifierToBlockChainId;
    mapping(uint256 blockChainId => uint16 messagingProtocolChainIdentifier) _blockChainIdToChainIdentifier;

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

    // --- Chain ID Functions --- //

    /** @dev Can only be called once for every chain. */
    function setChainMap(
        uint16 messagingProtocolChainIdentifier,
        uint256 chainId
    ) onlyOwner external {
        // Check that the inputs havn't been mistakenly called with 0 values.
        if (messagingProtocolChainIdentifier == 0) revert ZeroValue();
        if (chainId == 0) revert ZeroValue();

        // This call only allows setting either value once, then they are done for.
        // We need to check if they are currently unset.
        if (_chainIdentifierToBlockChainId[messagingProtocolChainIdentifier] != 0) revert NonZeroValue();
        if (_blockChainIdToChainIdentifier[chainId] != 0) revert NonZeroValue();

        _chainIdentifierToBlockChainId[messagingProtocolChainIdentifier] = chainId;
        _blockChainIdToChainIdentifier[chainId] = messagingProtocolChainIdentifier;

        emit MapMessagingProtocolIdentifierToChainId(messagingProtocolChainIdentifier, chainId);
    }

    function getChainIdentifierToBlockChainId(
        uint16 messagingProtocolChainIdentifier
    ) external view returns (uint256) {
        return _chainIdentifierToBlockChainId[messagingProtocolChainIdentifier];
    }

    function getBlockChainIdtoChainIdentifier(
        uint256 chainId
    ) external view returns (uint16) {
        return _blockChainIdToChainIdentifier[chainId];
    }

    // --- Sending Proofs & Generalised Incentives --- //

    /** @notice Submits proofs that have been stored in this oracle directly to Wormhole. */
    function submit(
        address proofSource,
        bytes[] calldata payloads
    ) public payable returns (uint256 refund) {
        // Check if the payloads are valid.
        if (!IPayloadCreator(proofSource).areValidPayloads(payloads)) revert NotAllPayloadsValid(); 

        // Payloads are good. We can submit them on behalf of proofSource.
        return _submit(proofSource, payloads);
    }

    // --- Wormhole Logic --- //

    /**
     * @notice Submits a proof the associated messaging protocol.
     * @dev Refunds excess value ot msg.sender. 
     */
    function _submit(
        address source,
        bytes[] calldata payloads
    ) internal returns (uint256 refund) {
        // This call fails if fillDeadlines.length < outputs.length
        bytes memory message = PayloadEncodingLibrary.encodeMessage(IdentifierLib.getIdentifier(source, address(uint160(uint128(uint160(address(this)))))), payloads);

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

    function receiveMessage(
        bytes calldata rawMessage
    ) external {
        (uint16 remoteMessagingProtocolChainIdentifier, bytes32 remoteSenderIdentifier, bytes calldata message) = _verifyPacket(rawMessage);
        (bytes32 identifierFromMessage, bytes32[] memory payloadHashes) = PayloadEncodingLibrary.decodeMessage(message);

        // Construct the identifier
        bytes32 senderIdentifier = IdentifierLib.enhanceIdentifier(remoteSenderIdentifier, identifierFromMessage);

        // Map remoteMessagingProtocolChainIdentifier to canonical chain id. This ensures we use canonical ids.
        uint256 remoteChainId = _chainIdentifierToBlockChainId[remoteMessagingProtocolChainIdentifier];
        // Store payload attestations;
        uint256 numPayloads = payloadHashes.length;
        for (uint256 i; i < numPayloads; ++i) {
            _attestations[remoteChainId][senderIdentifier][payloadHashes[i]] = true;

            emit OutputProven(remoteChainId, senderIdentifier, payloadHashes[i]);
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
