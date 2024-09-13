// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

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

    mapping(bytes32 orderKey => uint256 fillDeadline) public filledOrders;

    constructor(address _escrow, address _mirror) BaseOracle(_escrow) {
        mirror = IBtcPrism(_mirror);
    }

    /**
     * @notice Slices the timestamp from a Bitcoin block header.
     */
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
     * @notice Loads the number of confirmations from the second last byte of the token.
     * @dev "0" confirmations are converted into 1.
     * How long does it take for us to get 99,9% confidence that a transaction will
     * be confirmable. Examine n identically distributed exponentially random variables
     * with rate 1/10. The sum of the random variables are distributed gamma(n, 1/10).
     * The 99,9% quantile of the distribution can be found in R as qgamma(0.999, n, 1/10)
     * 1 confirmations: 69 minutes.
     * 3 confirmations: 112 minutes.
     * 5 confirmations: 148 minutes.
     * 7 confimrations: 181 minutes.
     * You may wonder why the delta decreases as we increase confirmations?
     * That is the law of large numbers in action.
     */
    function _getNumConfirmations(bytes32 token) internal pure returns (uint8 numConfirmations) {
        // Shift 8 bits to move the second byte to the right.
        numConfirmations = uint8(uint256(token) >> 8);
        // If numConfirmations == 0, set it to 1.
        numConfirmations = numConfirmations == 0 ? 1 : numConfirmations;
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
     * @param embeddedData If provided, the next input (txOutIx+1) is checked to contain an op_return
     * with embeddedData as the payload.
     * @return sats Value of txOutIx TXO of the transaction.
     */
    function _validateUnderlyingPayment(
        uint256 minConfirmations,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes memory outputScript,
        bytes calldata embeddedData
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
        bytes memory txOutData;
        if (embeddedData.length > 0) {
            // Important, this function validate that blockHash = hash(inclusionProof.blockHeader);
            (sats, txOutScript, txOutData) = BtcProof.validateTxData(blockHash, inclusionProof, txOutIx);

            if (!BtcProof.compareScripts(outputScript, txOutScript)) revert ScriptMismatch(outputScript, txOutScript);

            // Get the expected op_return script. This prepend embeddedData with 0x6a + {push_length}.
            bytes memory opReturnData = BtcScript.embedOpReturn(embeddedData);
            if (!BtcProof.compareScripts(opReturnData, txOutData)) revert ScriptMismatch(opReturnData, txOutData);
            return sats;
        }

        // Important, this function validate that blockHash = hash(inclusionProof.blockHeader);
        (sats, txOutScript) = BtcProof.validateTx(blockHash, inclusionProof, txOutIx);

        if (!BtcProof.compareScripts(outputScript, txOutScript)) revert ScriptMismatch(outputScript, txOutScript);
    }

    /**
     * @notice Validate an output is correct.
     * @dev Specifically, this function uses the other validation functions and adds some
     * Bitcoin context surrounding it.
     * @param output Output to prove.
     * @param fillDeadline Proof Deadline of order
     * @param blockNum Bitcoin block number of the transaction that the output is included in.
     * @param inclusionProof Proof of inclusion. fillDeadline is validated against Bitcoin block timestamp.
     * @param txOutIx Index of the output in the transaction being proved.
     */
    function _verify(
        OutputDescription calldata output,
        uint32 fillDeadline,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx
    ) internal {
        _validateChain(output.chainId);
        _validateRemoteOracleAddress(output.remoteOracle);

        {
            // Check the timestamp. This is done before inclusionProof is checked for validity
            // so it can be manipulated but if it has been manipulated the next check (_validateUnderlyingPayment)
            // won't pass.
            uint256 timestamp = _getTimestampOfBlock(inclusionProof.blockHeader);

            // Validate that the timestamp gotten from the TX is within bounds.
            // This ensures a Bitcoin output cannot be "reused" forever.
            _validateTimestamp(uint32(timestamp), fillDeadline);
        }

        bytes memory outputScript = _bitcoinScript(output.token, output.recipient);
        uint256 numConfirmations = _getNumConfirmations(output.token);
        uint256 sats = _validateUnderlyingPayment(numConfirmations, blockNum, inclusionProof, txOutIx, outputScript, output.remoteCall);

        // Check that the amount matches exactly. This is important since if the assertion
        // was looser it will be much harder to protect against "double spends".
        if (sats != output.amount) revert BadAmount();

        bytes32 outputHash = _outputHash(output);
        _provenOutput[outputHash][fillDeadline] = true;
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
        uint32 fillDeadline,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes calldata previousBlockHeader
    ) internal {
        _validateChain(output.chainId);
        _validateRemoteOracleAddress(output.remoteOracle);

        {
            // Check the timestamp. This is done before inclusionProof is checked for validity
            // so it can be manipulated but if it has been manipulated the next check (_validateUnderlyingPayment)
            // won't pass.
            
            // Get block hash of the previousBlockHeader.
            bytes32 proposedPreviousBlockHash = BtcProof.getBlockHash(previousBlockHeader);
            // Load the actual previous block hash from the header of the block we just proved.
            bytes32 actualPreviousBlockHash = bytes32(Endian.reverse256(uint256(bytes32(inclusionProof.blockHeader[4:36]))));
            if (actualPreviousBlockHash != proposedPreviousBlockHash) {
                revert BlockhashMismatch(actualPreviousBlockHash, proposedPreviousBlockHash);
            }

            // Get the timestamp of the block we validated it for.
            uint256 timestamp = _getTimestampOfBlock(previousBlockHeader);

            // Validate that the timestamp gotten from the TX is within bounds.
            // This ensures a Bitcoin output cannot be "reused" forever.
            _validateTimestamp(uint32(timestamp), fillDeadline);
        }

        bytes memory outputScript = _bitcoinScript(output.token, output.recipient);
        uint256 numConfirmations = _getNumConfirmations(output.token);
        uint256 sats = _validateUnderlyingPayment(numConfirmations, blockNum, inclusionProof, txOutIx, outputScript, output.remoteCall);

        // Check that the amount matches exactly. This is important since if the assertion
        // was looser it will be much harder to protect against "double spends".
        if (sats != output.amount) revert BadAmount();

        bytes32 outputHash = _outputHash(output);
        _provenOutput[outputHash][fillDeadline] = true;
    }

    /**
     * @notice Validate an output is correct.
     * @dev Specifically, this function uses the other validation functions and adds some
     * Bitcoin context surrounding it.
     * @param output Output to prove.
     * @param fillDeadline Proof Deadline of order
     * @param blockNum Bitcoin block number of the transaction that the output is included in.
     * @param inclusionProof Proof of inclusion. fillDeadline is validated against Bitcoin block timestamp.
     * @param txOutIx Index of the output in the transaction being proved.
     */
    function verify(
        OutputDescription calldata output,
        uint32 fillDeadline,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx
    ) external {
        _verify(output, fillDeadline, blockNum, inclusionProof, txOutIx);
    }

    /**
     * @notice Function overload of verify but allows specifying an older block.
     * @dev This function technically extends the verification of outputs 1 block (~10 minutes)
     * into the past beyond what _validateTimestamp would ordinary allow.
     * The purpose is to protect against slow block mining. Even if it took days to get confirmation on a transaction,
     * it would still be possible to include the proof with a valid time. (assuming the oracle period isn't over yet).
     */
    function verify(
        OutputDescription calldata output,
        uint32 fillDeadline,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes calldata previousBlockHeader
    ) external {
        _verify(output, fillDeadline, blockNum, inclusionProof, txOutIx, previousBlockHeader);
    }
}
