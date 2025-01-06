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

import "../OutputEncodingLibrary.sol";


import "forge-std/console.sol";
/**
 * @dev Oracles are also fillers
 */
abstract contract WormholeOracle is BaseOracle, IMessageEscrowStructs, WormholeVerifier, Ownable {
    error AlreadySet();
    error RemoteCallTooLarge();

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

    //--- Chain config ---//

    /**
     * @notice Defines the map between the messaging protocol and chainIds.
     * @dev Can only be called once for each chain.
     */
    function setRemoteImplementation(
        uint16 chainIdentifier,
        uint32 blockChainIdOfChainIdentifier
    ) external onlyOwner {
        // Check that we havn't set blockChainIdOfChainIdentifier yet.
        if (_blockChainIdToChainIdentifier[blockChainIdOfChainIdentifier] != 0) revert AlreadySet();
    
        _blockChainIdToChainIdentifier[blockChainIdOfChainIdentifier] = chainIdentifier;
        _chainIdentifierToBlockChainId[chainIdentifier] = blockChainIdOfChainIdentifier;
        emit MapMessagingProtocolIdentifierToChainId(chainIdentifier, blockChainIdOfChainIdentifier);
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
     * @param proofs Proof storage state for each output
     */
    function _submit(
        bytes32[] calldata orderIds,
        OutputDescription[] calldata outputs,
        ProofStorage[] memory proofs
    ) internal {
        // This call fails if fillDeadlines.length < outputs.length
        bytes memory message = OutputEncodingLibrary._encodeMessage(orderIds, outputs, proofs);

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
     */
    function submit(
        bytes32[] calldata orderIds,
        OutputDescription[] calldata outputs
    ) public payable {
        uint256 numOutputs = outputs.length;
        ProofStorage[] memory proofContexts = new ProofStorage[](numOutputs);
        unchecked {
            for (uint256 i; i < numOutputs; ++i) {
                OutputDescription calldata output = outputs[i];
                // The chainId of the output has to match this chain. This is required to ensure that it originated
                // here.
                _validateChain(bytes32(output.chainId));
                // Validate that this contract made the original proof (other oracles can't proxy proofs)
                _IAmRemoteOracle(output.remoteOracle); 
                // Validate that we have proofs for each output.
                proofContexts[i] = _provenOutput[orderIds[i]][output.remoteOracle][_outputHash(output)];
                if (proofContexts[i].solver != address(0)) {
                    revert CannotProveOrder();
                }
            }
        }
        // The submit call will fail if fillDeadlines.length < outputs.length.
        // This call also refunds excess value sent.
        _submit(orderIds, outputs, proofContexts);
    }

    function receiveMessage(
        bytes calldata rawMessage
    ) external {
        (uint16 sourceIdentifier, bytes32 remoteOracle, bytes calldata message) = _verifyPacket(rawMessage);

        (bytes32[2][] memory orderIdOutputHashes, ProofStorage[] memory proofContext) = OutputEncodingLibrary._decodeMessage(message);

        uint256 numOutputs = orderIdOutputHashes.length;

        // Load the expected chainId (not the messaging protocol identifier).
        uint32 expectedBlockChainId = _chainIdentifierToBlockChainId[sourceIdentifier];
        for (uint256 i; i < numOutputs; ++i) {
            bytes32[2] memory orderIdAndOutputHash = orderIdOutputHashes[i];
            bytes32 orderId = orderIdAndOutputHash[0];
            bytes32 outputHash = orderIdAndOutputHash[1];
            _provenOutput[orderId][remoteOracle][outputHash] = proofContext[i];

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
