// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { NoBlock, TooFewConfirmations } from "bitcoinprism-evm/src/interfaces/IBtcTxVerifier.sol";
import { BtcProof, BtcTxProof, ScriptMismatch } from "bitcoinprism-evm/src/library/BtcProof.sol";
import { BtcScript } from "bitcoinprism-evm/src/library/BtcScript.sol";

import { OrderKey, OutputDescription } from "../interfaces/Structs.sol";
import { BitcoinOracle } from "./BitcoinOracle.sol";

import { ICitrea } from "./interfaces/ICitrea.sol";

/**
 * @dev Bitcoin oracle using the Citrea ABI.
 */
contract CitreaOracle is BitcoinOracle {

    constructor(address _escrow, address _citrea) BitcoinOracle(_escrow, _citrea) {
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
    ) override internal view returns (uint256 sats) {
        // Isolate height check. This decreases gas cost slightly.
        {
            uint256 currentHeight = ICitrea(LIGHT_CLIENT).blockNumber();

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
        bytes32 blockHash = ICitrea(LIGHT_CLIENT).blockHashes(blockNum);

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
}
