// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

struct BitcoinPayment {
    uint64 amount;
    bytes outputScript;
}

import { Endian } from "bitcoinprism-evm/src/Endian.sol";
import { IBtcPrism } from "bitcoinprism-evm/src/interfaces/IBtcPrism.sol";
import { InvalidProof, NoBlock, TooFewConfirmations } from "bitcoinprism-evm/src/interfaces/IBtcTxVerifier.sol";
import { BtcProof, BtcTxProof, ScriptMismatch } from "bitcoinprism-evm/src/library/BtcProof.sol";
import { AddressType, BitcoinAddress, BtcScript } from "bitcoinprism-evm/src/library/BtcScript.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { Output } from "../interfaces/ISettlementContract.sol";
import { OrderKey } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";
import { BaseOracle } from "./BaseOracle.sol";

/**
 * Bitcoin oracle can operate in 2 modes:
 * 1. Directly Oracle. This requires a local light client along side the relevant reactor.
 * 2. Indirectly oracle through the bridge oracle. This requires a local light client and a bridge connection to the relevant reactor.
 */
contract BitcoinOracle is BaseOracle {
    // The Bitcoin Identifier (0xBB) is set in the 20'th byte (from right). This ensures
    // That implementations that only read the last 20 bytes, can still notice
    // that this is a Bitcoin address.
    bytes30 constant BITCOIN_AS_TOKEN = 0x000000000000000000000000BB0000000000000000000000000000000000;
    IBtcPrism public immutable mirror;

    error BadDestinationIdentifier();
    error BadAmount();
    error BadTokenFormat();
    error BlockhashMismatch(bytes32 actual, bytes32 proposed);

    bytes32 constant BITCOIN_DESTINATION_Identifier = bytes32(uint256(0x0B17C012)); // Bitcoin

    uint256 constant MIN_CONFIRMATIONS = 3; // TODO: Verify.

    mapping(bytes32 orderKey => uint256 fillTime) public filledOrders;

    constructor(IBtcPrism _mirror, address _escrow) BaseOracle(_escrow) {
        mirror = _mirror;
    }

    function _getTimestampOfBlock(bytes calldata blockHeader) internal pure returns (uint256 timestamp) {
        uint32 time = uint32(bytes4(blockHeader[68:68 + 4]));
        timestamp = Endian.reverse32(time);
    }

    /**
     * @notice Returns the associated Bitcoin script given an order token (sets for Bitcoin) & destination (scriptHash)
     */
    function _bitcoinScript(bytes32 token, bytes32 scriptHash) internal pure returns (bytes memory script) {
        // Check for the Bitcoin signifier:
        if (bytes30(token) != BITCOIN_AS_TOKEN) revert BadTokenFormat();

        AddressType bitcoinAddressType = AddressType(uint8(uint256(token)));

        return BtcScript.getBitcoinScript(bitcoinAddressType, scriptHash);
    }

    /**
     * @notice Validate the underlying Bitcoin payment. Does not return when it happened.
     */
    function _validateUnderlyingPayment(
        uint256 minConfirmations,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes memory outputScript
    ) internal view returns (uint256 sats) {
        // Isolate correct height check. This decreases gas cost slightly.
        {
            uint256 currentHeight = mirror.getLatestBlockHeight();

            if (currentHeight < blockNum) revert NoBlock(currentHeight, blockNum);

            unchecked {
                // Unchecked: currentHeight >= blockNum => currentHeight - blockNum >= 0
                // Bitcoin block heights are smaller than timestamp :)
                if (currentHeight + 1 - blockNum < minConfirmations) {
                    revert TooFewConfirmations(currentHeight + 1 - blockNum, minConfirmations);
                }
            }
        }

        bytes32 blockHash = mirror.getBlockHash(blockNum);

        bytes memory txOutScript;
        (sats, txOutScript) = BtcProof.validateTx(blockHash, inclusionProof, txOutIx);

        if (!BtcProof.compareScripts(outputScript, txOutScript)) revert ScriptMismatch(outputScript, txOutScript);
    }

    /**
     * @notice Verifies a payment and returns the time of the block it happened in.
     */
    function _verifyPayment(
        uint256 minConfirmations,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes memory outputScript
    ) internal view returns (uint256 sats, uint256 timestamp) {
        sats = _validateUnderlyingPayment(minConfirmations, blockNum, inclusionProof, txOutIx, outputScript);

        // Get the timestamp of the block we validated it for.
        timestamp = _getTimestampOfBlock(inclusionProof.blockHeader);
    }

    /**
     * @notice Verifies a payment and returns the time of the block before it happened.
     * This allows one to properly match a transaction against an order if no Bitcoin block happened for a long period of time.
     */
    function _verifyPayment(
        uint256 minConfirmations,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes memory outputScript,
        bytes calldata previousBlockHeader
    ) internal view returns (uint256 sats, uint256 timestamp) {
        sats = _validateUnderlyingPayment(minConfirmations, blockNum, inclusionProof, txOutIx, outputScript);

        // Get block hash of the previousBlockHeader.
        bytes32 proposedPreviousBlockHash = BtcProof.getBlockHash(previousBlockHeader);
        // Load the actual previous block hash from the header of the block we just proved.
        bytes32 actualPreviousBlockHash = bytes32(Endian.reverse256(uint256(bytes32(inclusionProof.blockHeader[4:36]))));
        if (actualPreviousBlockHash != proposedPreviousBlockHash) {
            revert BlockhashMismatch(actualPreviousBlockHash, proposedPreviousBlockHash);
        }

        // Get the timestamp of the block we validated it for.
        timestamp = _getTimestampOfBlock(previousBlockHeader);
    }

    // TODO: convert to verifying a single output + some identifier.
    function _verify(
        Output calldata output,
        uint32 fillTime,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx
    ) internal {
        if (output.chainId != block.chainid) revert BadDestinationIdentifier();

        bytes memory outputScript = _bitcoinScript(output.token, output.recipient);

        (uint256 sats, uint256 timestamp) =
            _verifyPayment(MIN_CONFIRMATIONS, blockNum, inclusionProof, txOutIx, outputScript);

        _validateTimestamp(uint32(timestamp), fillTime);

        if (sats != output.amount) revert BadAmount();

        bytes32 outputHash = _outputHash(output);
        _provenOutput[outputHash][fillTime][bytes32(0)] = true;
    }

    function _verify(
        Output calldata output,
        uint32 fillTime,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes calldata previousBlockHeader
    ) internal {
        if (output.chainId != block.chainid) revert BadDestinationIdentifier();

        bytes memory outputScript = _bitcoinScript(output.token, output.recipient);

        (uint256 sats, uint256 timestamp) =
            _verifyPayment(MIN_CONFIRMATIONS, blockNum, inclusionProof, txOutIx, outputScript, previousBlockHeader);

        _validateTimestamp(uint32(timestamp), fillTime);

        if (sats != output.amount) revert BadAmount();

        bytes32 outputHash = _outputHash(output);
        _provenOutput[outputHash][fillTime][bytes32(0)] = true;
    }
}
