// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "../../../src/interfaces/Structs.sol";
import "./blocksinfo.t.sol";

import { Endian } from "bitcoinprism-evm/src/Endian.sol";
import { IBtcPrism } from "bitcoinprism-evm/src/interfaces/IBtcPrism.sol";
import { BtcProof, BtcTxProof, ScriptMismatch } from "bitcoinprism-evm/src/library/BtcProof.sol";

import { FillDeadlineInPast } from "../../../src/interfaces/Errors.sol";

import { DeployBitcoinOracle } from "../../../script/oracle/DeployBitcoinOracle.s.sol";
import { BitcoinOracle } from "../../../src/oracles/BitcoinOracle.sol";
import { Test } from "forge-std/Test.sol";

contract TestBitcoinOracle is Test, DeployBitcoinOracle {
    BitcoinOracle bitcoinOracle;

    function setUp() public {
        bitcoinOracle = deploy("mainnet");
    }

    function test_verify(bytes memory remoteCall, uint32 timeIncrement) public {
        vm.assume(timeIncrement <= 7 days);
        OutputDescription memory output = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(bitcoinOracle)))),
            token: bytes32(bytes.concat(hex"000000000000000000000000BC000000000000000000000000000000000000", UTXO_TYPE)),
            recipient: bytes32(PHASH),
            amount: SATS_AMOUNT,
            chainId: uint32(block.chainid),
            remoteCall: remoteCall
        });

        BtcTxProof memory inclusionProof = BtcTxProof({
            blockHeader: BLOCK_HEADER,
            txId: TX_ID,
            txIndex: TX_INDEX,
            txMerkleProof: TX_MERKLE_PROOF,
            rawTx: RAW_TX
        });

        bitcoinOracle.verify(output, uint32(BLOCK_TIME) + timeIncrement, BLOCK_HEIGHT, inclusionProof, TX_OUTPUT_INDEX);

        assert(bitcoinOracle.isProven(output, uint32(BLOCK_TIME) + timeIncrement));
    }

    function test_verify_with_previous_block_header(bytes memory remoteCall, uint32 timeIncrement) public {
        vm.assume(timeIncrement < 7 days);
        OutputDescription memory output = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(bitcoinOracle)))),
            token: bytes32(bytes.concat(hex"000000000000000000000000BC000000000000000000000000000000000000", UTXO_TYPE)),
            recipient: bytes32(PHASH),
            amount: SATS_AMOUNT,
            chainId: uint32(block.chainid),
            remoteCall: remoteCall
        });

        BtcTxProof memory inclusionProof = BtcTxProof({
            blockHeader: BLOCK_HEADER,
            txId: TX_ID,
            txIndex: TX_INDEX,
            txMerkleProof: TX_MERKLE_PROOF,
            rawTx: RAW_TX
        });
        bitcoinOracle.verify(
            output, uint32(BLOCK_TIME) + timeIncrement, BLOCK_HEIGHT, inclusionProof, TX_OUTPUT_INDEX, PREV_BLOCK_HEADER
        );
        assert(bitcoinOracle.isProven(output, uint32(BLOCK_TIME) + timeIncrement));
    }

    function test_verify_after_block_sumbission(bytes memory remoteCall, uint32 timeIncrement) public {
        vm.assume(timeIncrement < 7 days);
        bitcoinOracle.mirror().submit(NEXT_BLOCK_HEIGHT, NEXT_BLOCK_HEADER);
        OutputDescription memory outputNextBlock = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(bitcoinOracle)))),
            token: bytes32(
                bytes.concat(hex"000000000000000000000000BC000000000000000000000000000000000000", NEXT_UTXO_TYPE)
            ),
            recipient: bytes32(NEXT_PHASH),
            amount: NEXT_SATS_AMOUNT,
            chainId: uint32(block.chainid),
            remoteCall: remoteCall
        });

        BtcTxProof memory inclusionProofNextBlock = BtcTxProof({
            blockHeader: NEXT_BLOCK_HEADER,
            txId: NEXT_TX_ID,
            txIndex: NEXT_TX_INDEX,
            txMerkleProof: NEXT_TX_MERKLE_PROOF,
            rawTx: NEXT_RAW_TX
        });

        bitcoinOracle.verify(
            outputNextBlock,
            uint32(NEXT_BLOCK_TIME) + timeIncrement,
            NEXT_BLOCK_HEIGHT,
            inclusionProofNextBlock,
            NEXT_TX_OUTPUT_INDEX
        );
        assert(bitcoinOracle.isProven(outputNextBlock, uint32(NEXT_BLOCK_TIME) + timeIncrement));
    }

    ///Invalid test cases///

    function test_invalid_fill_deadline(bytes memory remoteCall, uint32 timeDecrement) public {
        vm.assume(timeDecrement < BLOCK_TIME && timeDecrement > 0);
        OutputDescription memory output = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(bitcoinOracle)))),
            token: bytes32(bytes.concat(hex"000000000000000000000000BC000000000000000000000000000000000000", UTXO_TYPE)),
            recipient: bytes32(PHASH),
            amount: SATS_AMOUNT,
            chainId: uint32(block.chainid),
            remoteCall: remoteCall
        });

        BtcTxProof memory inclusionProof = BtcTxProof({
            blockHeader: BLOCK_HEADER,
            txId: TX_ID,
            txIndex: TX_INDEX,
            txMerkleProof: TX_MERKLE_PROOF,
            rawTx: RAW_TX
        });

        vm.expectRevert(FillDeadlineInPast.selector);
        bitcoinOracle.verify(output, uint32(BLOCK_TIME - timeDecrement), BLOCK_HEIGHT, inclusionProof, TX_OUTPUT_INDEX);
    }

    function test_revert_bad_amount(bytes memory remoteCall, uint32 timeIncrement, uint256 amount) public {
        vm.assume(amount != NEXT_SATS_AMOUNT);
        vm.assume(timeIncrement < 7 days);

        bitcoinOracle.mirror().submit(NEXT_BLOCK_HEIGHT, NEXT_BLOCK_HEADER);
        OutputDescription memory outputNextBlock = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(bitcoinOracle)))),
            token: bytes32(
                bytes.concat(hex"000000000000000000000000BC000000000000000000000000000000000000", NEXT_UTXO_TYPE)
            ),
            recipient: bytes32(NEXT_PHASH),
            amount: amount,
            chainId: uint32(block.chainid),
            remoteCall: remoteCall
        });

        BtcTxProof memory inclusionProofNextBlock = BtcTxProof({
            blockHeader: NEXT_BLOCK_HEADER,
            txId: NEXT_TX_ID,
            txIndex: NEXT_TX_INDEX,
            txMerkleProof: NEXT_TX_MERKLE_PROOF,
            rawTx: NEXT_RAW_TX
        });

        vm.expectRevert(abi.encodeWithSignature("BadAmount()"));

        bitcoinOracle.verify(
            outputNextBlock,
            uint32(NEXT_BLOCK_TIME + timeIncrement),
            NEXT_BLOCK_HEIGHT,
            inclusionProofNextBlock,
            NEXT_TX_OUTPUT_INDEX
        );
    }

    function test_revert_fill_deadline_far_in_future(bytes memory remoteCall, uint24 timeIncrement) public {
        vm.assume(timeIncrement > 7 days);
        OutputDescription memory output = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(bitcoinOracle)))),
            token: bytes32(bytes.concat(hex"000000000000000000000000BC000000000000000000000000000000000000", UTXO_TYPE)),
            recipient: bytes32(PHASH),
            amount: SATS_AMOUNT,
            chainId: uint32(block.chainid),
            remoteCall: remoteCall
        });

        BtcTxProof memory inclusionProof = BtcTxProof({
            blockHeader: BLOCK_HEADER,
            txId: TX_ID,
            txIndex: TX_INDEX,
            txMerkleProof: TX_MERKLE_PROOF,
            rawTx: RAW_TX
        });

        vm.expectRevert(abi.encodeWithSignature("FillDeadlineFarInFuture()"));
        bitcoinOracle.verify(output, uint32(BLOCK_TIME) + timeIncrement, BLOCK_HEIGHT, inclusionProof, TX_OUTPUT_INDEX);
    }

    // Check against the hash of next block not the previous so it should revert
    function test_revert_block_hash_mismatch(bytes memory remoteCall, uint32 timeIncrement) public {
        vm.assume(timeIncrement < 7 days);

        OutputDescription memory output = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(bitcoinOracle)))),
            token: bytes32(bytes.concat(hex"000000000000000000000000BC000000000000000000000000000000000000", UTXO_TYPE)),
            recipient: bytes32(PHASH),
            amount: SATS_AMOUNT,
            chainId: uint32(block.chainid),
            remoteCall: remoteCall
        });

        BtcTxProof memory inclusionProof = BtcTxProof({
            blockHeader: BLOCK_HEADER,
            txId: TX_ID,
            txIndex: TX_INDEX,
            txMerkleProof: TX_MERKLE_PROOF,
            rawTx: RAW_TX
        });

        bytes32 expectedBlockHash = this._getBlockHashFromHeader(NEXT_BLOCK_HEADER);
        bytes32 actualBlockHash = this._getPreviousBlockHashFromHeader(inclusionProof.blockHeader);
        vm.expectRevert(
            abi.encodeWithSignature("BlockhashMismatch(bytes32,bytes32)", actualBlockHash, expectedBlockHash)
        );
        bitcoinOracle.verify(
            output, uint32(BLOCK_TIME) + timeIncrement, BLOCK_HEIGHT, inclusionProof, TX_OUTPUT_INDEX, NEXT_BLOCK_HEADER
        );
    }

    function test_revert_bad_token(
        bytes32 token,
        uint256 amount,
        bytes memory remoteCall,
        bytes32 recipient,
        uint32 timeIncrement
    ) public {
        vm.assume(timeIncrement < 7 days);
        vm.assume(bytes30(token) != hex"000000000000000000000000BC0000000000000000000000000000000000");
        OutputDescription memory output = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(bitcoinOracle)))),
            token: token,
            recipient: recipient,
            amount: amount,
            chainId: uint32(block.chainid),
            remoteCall: remoteCall
        });

        BtcTxProof memory inclusionProof = BtcTxProof({
            blockHeader: BLOCK_HEADER,
            txId: TX_ID,
            txIndex: TX_INDEX,
            txMerkleProof: TX_MERKLE_PROOF,
            rawTx: RAW_TX
        });

        vm.expectRevert(abi.encodeWithSignature("BadTokenFormat()"));
        bitcoinOracle.verify(output, uint32(BLOCK_TIME) + timeIncrement, BLOCK_HEIGHT, inclusionProof, TX_OUTPUT_INDEX);
    }

    function test_revert_no_block(
        uint256 blockHeight,
        uint256 amount,
        bytes memory remoteCall,
        bytes32 recipient,
        uint32 timeIncrement
    ) public {
        vm.assume(blockHeight > BLOCK_HEIGHT);
        vm.assume(timeIncrement < 7 days);
        OutputDescription memory output = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(bitcoinOracle)))),
            token: bytes32(bytes.concat(hex"000000000000000000000000BC000000000000000000000000000000000000", UTXO_TYPE)),
            recipient: recipient,
            amount: amount,
            chainId: uint32(block.chainid),
            remoteCall: remoteCall
        });

        BtcTxProof memory inclusionProof = BtcTxProof({
            blockHeader: BLOCK_HEADER,
            txId: TX_ID,
            txIndex: TX_INDEX,
            txMerkleProof: TX_MERKLE_PROOF,
            rawTx: RAW_TX
        });
        vm.expectRevert(abi.encodeWithSignature("NoBlock(uint256,uint256)", BLOCK_HEIGHT, blockHeight));

        bitcoinOracle.verify(output, uint32(BLOCK_TIME) + timeIncrement, blockHeight, inclusionProof, TX_OUTPUT_INDEX);
    }

    function _getBlockHashFromHeader(bytes calldata blockHeader) public pure returns (bytes32 blockHash) {
        blockHash = BtcProof.getBlockHash(blockHeader);
    }

    function _getPreviousBlockHashFromHeader(bytes calldata blockHeader)
        public
        pure
        returns (bytes32 previousBlockHash)
    {
        previousBlockHash = bytes32(Endian.reverse256(uint256(bytes32(blockHeader[4:36]))));
    }
}
