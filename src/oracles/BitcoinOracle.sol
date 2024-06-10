// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

struct BitcoinPayment {
    uint64 amount;
    bytes outputScript;
}

import { IBtcPrism } from "bitcoinprism-evm/src/interfaces/IBtcPrism.sol";
import { NoBlock, TooFewConfirmations, InvalidProof } from "bitcoinprism-evm/src/interfaces/IBtcTxVerifier.sol";
import { BtcProof, BtcTxProof, ScriptMismatch } from "bitcoinprism-evm/src/library/BtcProof.sol";
import { BitcoinAddress, AddressType, BtcScript } from "bitcoinprism-evm/src/library/BtcScript.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { OrderKey } from "../interfaces/Structs.sol";
import { Output } from "../interfaces/ISettlementContract.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";

/**
 * Bitcoin oracle can operate in 2 modes:
 * 1. Directly Oracle. This requires a local light client along side the relevant reactor.
 * 2. Indirectly oracle through the bridge oracle. This requires a local light client and a bridge connection to the relevant reactor.
 */
abstract contract BitcoinOracle is ICrossChainReceiver, IMessageEscrowStructs {
    bytes1 constant BITCOIN_PREFIX = 0xBB;
    IBtcPrism public immutable mirror;

    error BadDestinationIdentifier();
    error BadAmount();
    error BadTokenFormat();

    bytes32 constant BITCOIN_DESTINATION_Identifier = bytes32(uint256(0x0B17C012)); // Bitcoin

    uint256 constant MIN_CONFIRMATIONS = 3; // TODO: Verify.

    mapping(bytes32 orderKey => uint256 fillTime) public filledOrders;

    constructor(IBtcPrism _mirror) {
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
        // TODO: See Bitcoin Prism's payment validator.
        // {
        //     uint256 currentHeight = mirror.getLatestBlockHeight();

        //     if (currentHeight < blockNum) revert NoBlock(currentHeight, blockNum);

        //     unchecked {
        //         if (currentHeight + 1 - blockNum < minConfirmations) revert TooFewConfirmations(currentHeight + 1 - blockNum, minConfirmations);
        //     }
        // }

        // bytes32 blockHash = mirror.getBlockHash(blockNum);

        // bytes memory txOutScript;
        // (sats, txOutScript) = BtcProof.validateTx(
        //     blockHash,
        //     inclusionProof,
        //     txOutIx
        // );

        // // TODO: Do we want to also get the timestamp of the previous block? What if there is just not a block for a very long time?
        // uint32 time = uint32(bytes4(inclusionProof.blockHeader[ixT:ixT + 4]));
        // timestamp = Endian.reverse32(time);

        // if (!BtcProof.compareScripts(outputScript, txOutScript)) revert ScriptMismatch(outputScript, txOutScript);
    }

    // TODO: convert to verifying a single output + some identifier.
    function _verify(
        Output calldata output,
        OrderKey calldata orderKey,
        uint256 blockNum,
        BtcTxProof calldata inclusionProof,
        uint256 txOutIx
    ) internal {
        // TODO: use output.chainId to verify that this is the correct SPV client
        if (output.chainId != block.chainid) revert BadDestinationIdentifier();

        bytes memory outputScript = bytes.concat(output.recipient);
        (uint256 sats, uint256 timestamp) =
            _verifyPayment(MIN_CONFIRMATIONS, blockNum, inclusionProof, txOutIx, outputScript);

        if (sats != output.amount) revert BadAmount();

        // We don't check if the transaction has been verified before (since there isn't actually any filling being done).
        // instead we just set it as filled.
        // filledOrders[orderKey] = block.timestamp; // TODO: Use correct timestamp
    }

    //--- Sending Proofs ---//

    // TODO: figure out what the best best interface for this function is
    function _submit(
        uint256 filledTime,
        OrderKey calldata orderKey,
        address reactor,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) internal {
        // TODO: Figure out a better idea than abi.encode
        bytes memory message = abi.encode(reactor, filledTime, orderKey);
        // escrow.submitMessage(destinationIdentifier, destinationAddress, message, incentive);
    }

    //--- Solver Interface ---//

    function submit(
        OrderKey calldata orderKey,
        address reactor,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable {
        uint256 filledTime = 0; // filledOrders[orderKey];
        // if (fillStatus == 0) revert NotFilled();

        _submit(filledTime, orderKey, reactor, destinationIdentifier, destinationAddress, incentive, deadline);
    }
}
