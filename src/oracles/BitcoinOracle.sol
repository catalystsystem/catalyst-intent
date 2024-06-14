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
    bytes1 constant BITCOIN_PREFIX = 0xBB;
    IBtcPrism public immutable mirror;

    error BadDestinationIdentifier();
    error BadAmount();
    error BadTokenFormat();

    bytes32 constant BITCOIN_DESTINATION_Identifier = bytes32(uint256(0x0B17C012)); // Bitcoin

    uint256 constant MIN_CONFIRMATIONS = 3; // TODO: Verify.

    mapping(bytes32 orderKey => uint256 fillTime) public filledOrders;

    constructor(IBtcPrism _mirror, address _escrow) BaseOracle(_escrow) {
        mirror = _mirror;
    }

    function _bitcoinScript(bytes32 token, bytes32 scriptHash) internal pure returns (bytes memory script) {
        // TODO: Check the 12'th byte (as if it was an address?)
        // Check for the Bitcoin signifier:
        if (bytes1(token) != BITCOIN_PREFIX) revert BadTokenFormat();

        AddressType bitcoinAddressType = AddressType(uint8(uint256(token)));

        return BtcScript.getBitcoinScript(bitcoinAddressType, scriptHash);
    }

    // TODO: Implement a way to provide the previous block header.
    // This will give us a better way to determine when transaction was originated.
    function _verifyPayment(
        uint256 minConfirmations,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx,
        bytes memory outputScript
    ) internal view returns (uint256 sats, uint256 timestamp) {
        {
            uint256 currentHeight = mirror.getLatestBlockHeight();

            if (currentHeight < blockNum) revert NoBlock(currentHeight, blockNum);

            unchecked {
                if (currentHeight + 1 - blockNum < minConfirmations) {
                    revert TooFewConfirmations(currentHeight + 1 - blockNum, minConfirmations);
                }
            }
        }

        bytes32 blockHash = mirror.getBlockHash(blockNum);

        bytes memory txOutScript;
        (sats, txOutScript) = BtcProof.validateTx(blockHash, inclusionProof, txOutIx);

        if (!BtcProof.compareScripts(outputScript, txOutScript)) revert ScriptMismatch(outputScript, txOutScript);

        // TODO: Get timestamp of previous block. This is pretty hard but doable. It requries us to get the "relevant" header and then check if that is a valid block.
        uint256 ixT = inclusionProof.blockHeader.length - 12;
        uint32 time = uint32(bytes4(inclusionProof.blockHeader[ixT:ixT + 4]));
        timestamp = Endian.reverse32(time);
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

        bytes32 outputHash = _outputHash(output, bytes32(0)); // TODO: salt
        _provenOutput[outputHash][fillTime][bytes32(0)] = true;
    }

    //--- Solver Interface ---//

    function submit(
        Output[] calldata outputs,
        uint32[] calldata fillTimes,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable {
        // TODO: verify the output first.
        _submit(outputs, fillTimes, destinationIdentifier, destinationAddress, incentive, deadline);
    }
}
