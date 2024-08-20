// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Endian } from "bitcoinprism-evm/src/Endian.sol";
import { IBtcPrism } from "bitcoinprism-evm/src/interfaces/IBtcPrism.sol";
import { InvalidProof, NoBlock, TooFewConfirmations } from "bitcoinprism-evm/src/interfaces/IBtcTxVerifier.sol";
import { BtcProof, BtcTxProof, ScriptMismatch } from "bitcoinprism-evm/src/library/BtcProof.sol";
import { AddressType, BitcoinAddress, BtcScript } from "bitcoinprism-evm/src/library/BtcScript.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { OrderKey, OutputDescription } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";
import { BaseOracle } from "./BaseOracle.sol";

/**
 * @dev Bitcoin oracle can operate in 2 modes:
 * 1. Directly Oracle. This requires a local light client along side the relevant reactor.
 * 2. Indirectly oracle through the bridge oracle. This requires a local light client and a bridge connection to the relevant reactor.
 * 0xB17C012
 */
contract BitcoinOracle is BaseOracle {
    // The Bitcoin Identifier (0xBC) is set in the 20'th byte (from right). This ensures
    // implementations that are only reading the last 20 bytes, still notice this is a Bitcoin address.
    // It also makes it more difficult for there to be a collision (even though low numeric value 
    // addresses are generally pre-compiles and thus would be safe).
    // This also add standardizes support for other light clients coins (Lightcoin 0x1C?)
    bytes30 constant BITCOIN_AS_TOKEN = 0x000000000000000000000000BC0000000000000000000000000000000000;
    IBtcPrism public immutable mirror;

    error BadDestinationIdentifier();
    error BadAmount();
    error BadTokenFormat();
    error BlockhashMismatch(bytes32 actual, bytes32 proposed);

    uint256 constant MIN_CONFIRMATIONS = 3; // TODO: Verify.

    mapping(bytes32 orderKey => uint256 fillTime) public filledOrders;

    constructor(IBtcPrism _mirror, address _escrow) BaseOracle(_escrow) {
        mirror = _mirror;
    }

    /** @notice Slices the timestamp from a Bitcoin block header. */
    function _getTimestampOfBlock(bytes calldata blockHeader) internal pure returns (uint256 timestamp) {
        uint32 time = uint32(bytes4(blockHeader[68:68 + 4]));
        timestamp = Endian.reverse32(time);
    }

    /**
     * @notice Returns the associated Bitcoin script given an order token (address type) & destination (script hash).
     * @param token Bitcoin signifier (checked) and an address version.
     * @param scriptHash Bitcoin address identifier hash. Public key hash, script hash, or witness hash.
     * @return script Bitcoin output script matching the given parameters.
     */
    function _bitcoinScript(bytes32 token, bytes32 scriptHash) internal pure returns (bytes memory script) {
        // Check for the Bitcoin signifier:
        if (bytes30(token) != BITCOIN_AS_TOKEN) revert BadTokenFormat();

        AddressType bitcoinAddressType = AddressType(uint8(uint256(token)));

        return BtcScript.getBitcoinScript(bitcoinAddressType, scriptHash);
    }

    /**
     * @notice Verifies the existence of a Bitcoin transaction and returns the number of satoshis associated
     * with output txOutIx of the transaction.
     * @dev Does not return _when_ it happened except that it happened on blockNum.
     * @param minConfirmations Number of confirmations before transaction is considered valid.
     * @param blockNum Block number of the transaction.
     * @param inclusionProof Proof for transaction & transaction data.
     * @param txOutIx Index of the transaction's outputs that is examined against the output script and sats.
     * @param outputScript The expected output script. Compared to the actual, reverts if different.
     * @return sats Value of txOutIx TXO of the transaction.
     */
    function _validateUnderlyingPayment(
        uint256 minConfirmations,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes memory outputScript
    ) internal view returns (uint256 sats) {
        // Isolate height check. This decreases gas cost slightly.
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

        // Load the expected hash for blockNum. This is the "security" call of the light client.
        // If block hash matches the hash of inclusionProof.blockHeader then we know it is a
        // valid block.
        bytes32 blockHash = mirror.getBlockHash(blockNum);

        bytes memory txOutScript;
        // Important, this function validate that blockHash = hash(inclusionProof.blockHeader);
        (sats, txOutScript) = BtcProof.validateTx(blockHash, inclusionProof, txOutIx);

        // TODO: Check if there are gas savings if we mlve scripts as hashes.
        if (!BtcProof.compareScripts(outputScript, txOutScript)) revert ScriptMismatch(outputScript, txOutScript);
    }

    /**
     * @notice Verifies a payment and returns the time of the block it happened in & transaction amount.
     * @param minConfirmations Number of confirmations before transaction is considered valid.
     * @param blockNum Block number of the transaction.
     * @param inclusionProof Proof for transaction & transaction data.
     * @param txOutIx Index of the transaction's outputs that is examined against the output script and sats.
     * @param outputScript The expected output script. Compared to the actual, reverts if different.
     * @return sats Value of txOutIx TXO of the transaction.
     * @return timestamp Timestamp of blockNum. Is derived from the inclusionProof block header but
     * the header is verified to belong to blockNum.
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
     * @notice Verifies a payment and returns the time of the block before it was included & transaction amount.
     * @dev This allows one to properly match a transaction against an order if no Bitcoin block happened for a long period of time.
     * @param minConfirmations Number of confirmations before transaction is considered valid.
     * @param blockNum Block number of the transaction.
     * @param inclusionProof Proof for transaction & transaction data.
     * @param txOutIx Index of the transaction's outputs that is examined against the output script and sats.
     * @param outputScript The expected output script. Compared to the actual, reverts if different.
     * @param previousBlockHeader The previous block header. Is checked for authenticity by loading
     * the actual previous block hash from the current block header. 
     * @return sats Value of txOutIx TXO of the transaction.
     * @return timestamp Timestamp of blockNum. Is derived from the inclusionProof block header but
     * the header is verified to belong to blockNum.
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

    /**
     * @notice Validate an output is correct.
     * @dev Specifically, this function uses the other validation functions and adds some
     * Bitcoin context surrounding it.
     * @param output Output to prove.
     * @param fillTime Proof Deadline of order
     * @param blockNum Bitcoin block number of the transaction that the output is included in.
     * @param inclusionProof Proof of inclusion. fillTime is validated against Bitcoin block timestamp.
     * @param txOutIx Index of the output in the transaction being proved.
     */
    function _verify(
        OutputDescription calldata output,
        uint32 fillTime,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx
    ) internal {
        // TODO: fix chainid to be based on the messaging protocol being used
        if (output.chainId != block.chainid) revert BadDestinationIdentifier();

        bytes memory outputScript = _bitcoinScript(output.token, output.recipient);

        (uint256 sats, uint256 timestamp) =
            _verifyPayment(MIN_CONFIRMATIONS, blockNum, inclusionProof, txOutIx, outputScript);

        // Validate that the timestamp gotten from the TX is within bounds.
        // This ensures a Bitcoin output cannot be "reused" forever.
        _validateTimestamp(uint32(timestamp), fillTime);

        // Check that the amount matches exactly. This is important since if the assertion
        // was looser it will be much harder to protect against "double spends".
        if (sats != output.amount) revert BadAmount();

        bytes32 outputHash = _outputHash(output);
        _provenOutput[outputHash][fillTime][bytes32(0)] = true;
    }

    /**
     * @notice Function overload of _verify but allows specifying an older block.
     * @dev This function technically extends the verification of outputs 1 block (~10 minutes)
     * into the past beyond what _validateTimestamp would ordinary allow.
     * The purpose is to protect against slow block mining. Even if it took days to get confirmation on a transaction,
     * it would still be possible to include the proof with a valid time. (assuming the oracle period isn't over yet).
     */
    function _verify(
        OutputDescription calldata output,
        uint32 fillTime,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes calldata previousBlockHeader
    ) internal {
        // TODO: fix chainid to be based on the messaging protocol being used
        if (output.chainId != block.chainid) revert BadDestinationIdentifier();

        bytes memory outputScript = _bitcoinScript(output.token, output.recipient);

        // Validate that the timestamp gotten from the TX is within bounds.
        // This ensures a Bitcoin output cannot be "reused" forever.
        (uint256 sats, uint256 timestamp) =
            _verifyPayment(MIN_CONFIRMATIONS, blockNum, inclusionProof, txOutIx, outputScript, previousBlockHeader);

        // Check that the amount matches exactly. This is important since if the assertion
        // was looser it will be much harder to protect against "double spends".
        _validateTimestamp(uint32(timestamp), fillTime);

        if (sats != output.amount) revert BadAmount();

        bytes32 outputHash = _outputHash(output);
        _provenOutput[outputHash][fillTime][bytes32(0)] = true;
    }

    // TODO: Expose these function
    /* 
    function verify(...) external {
        _verify(...)
    }
     */
}
