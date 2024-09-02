// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import { DeployBitcoinOracle } from "../../../script/Oracle/DeployBitcoinOracle.sol";
import { OracleHelperConfig } from "../../../script/Oracle/HelperConfig.sol";

import { OutputDescription } from "../../../src/interfaces/Structs.sol";
import { MockBitcoinOracle } from "../../mocks/MockBitcoinOracle.sol";

import { FillDeadlineInPast } from "../../../src/interfaces/Errors.sol";
import "./blockInfo.t.sol";
import { BtcPrism } from "bitcoinprism-evm/src/BtcPrism.sol";
import { BtcProof, BtcTxProof, ScriptMismatch } from "bitcoinprism-evm/src/library/BtcProof.sol";

contract TestBitcoinOracle is Test {
    MockBitcoinOracle bitcoinOracle;
    OracleHelperConfig oracleConfig;

    function setUp() public {
        DeployBitcoinOracle deployer = new DeployBitcoinOracle();
        (bitcoinOracle, oracleConfig) = deployer.run();
    }

    function test_verify() public {
        bitcoinOracle.verify(
            this._getOutput(),
            uint32(BLOCK_TIME + 1),
            BLOCK_HEIGHT,
            this._getInclusionProof(TX_MERKLE_PROOF),
            TX_OUTPUT_INDEX
        );
        assert(bitcoinOracle.isProven(this._getOutput(), uint32(BLOCK_TIME + 1)));
    }

    ///Invalid test cases///

    // function test_invalid_merkle_root() public {
    //     vm.expectRevert();
    //     bitcoinOracle.verify(
    //         this._getOutput(), uint32(BLOCK_TIME + 1), BLOCK_HEIGHT, this._getInclusionProof(hex"dead"), TX_OUTPUT_INDEX
    //     );
    // }

    function test_invalid_fill_deadline(uint32 timeDecrement) public {
        vm.assume(timeDecrement < BLOCK_TIME && timeDecrement > 0);
        OutputDescription memory outuput = this._getOutput();

        BtcTxProof memory inclusionProof = this._getInclusionProof(TX_MERKLE_PROOF);
        vm.expectRevert(FillDeadlineInPast.selector);
        bitcoinOracle.verify(outuput, uint32(BLOCK_TIME - timeDecrement), BLOCK_HEIGHT, inclusionProof, TX_OUTPUT_INDEX);
    }

    function _getOutput() public view returns (OutputDescription memory output) {
        return OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(bitcoinOracle)))),
            token: bytes32(bytes.concat(hex"000000000000000000000000BC000000000000000000000000000000000000", UTXO_TYPE)),
            recipient: bytes32(PHASH),
            amount: SATS_AMOUNT,
            chainId: uint32(block.chainid),
            remoteCall: ""
        });
    }

    function _getInclusionProof(bytes memory merkleProof) public pure returns (BtcTxProof memory inclusionProof) {
        return BtcTxProof({
            blockHeader: BLOCK_HEADER,
            txId: TX_ID,
            txIndex: TX_INDEX,
            txMerkleProof: merkleProof,
            rawTx: RAW_TX
        });
    }
}
