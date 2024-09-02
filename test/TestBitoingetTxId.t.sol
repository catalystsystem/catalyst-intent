// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { BtcProof } from "bitcoinprism-evm/src/library/BtcProof.sol";
import "forge-std/Test.sol";
import { Test } from "forge-std/Test.sol";

contract TestGetTxID is Test {
    function setUp() public { }

    function test_get_Tx_ID() public {
        bytes32 actualID = 0x3836352218be851ebb4685d7f3a22dde70a66b52a965e62c2a0bfa0988cdd0ba;
        bytes32 expectedID = this._getProof(this._getRawTX());

        assertEq(actualID, expectedID);
    }

    function _getRawTX() public pure returns (bytes memory) {
        return
        hex"0200000002e8fff13bde95811dd2f8a013331831fcc39443e79caf4c14d8c3be028f0263870000000000feffffffacc392249ba5582a4f713d8c8e87f284b5a8c7130623a122aea805324a29c6500200000000feffffff011bcc0100000000001976a914ec083c2cc912b54cabf3d5506671618bb652925188acf6190d00";
    }

    function _getProof(bytes calldata rawTx) public pure returns (bytes32) {
        return BtcProof.getTxID(rawTx);
    }
}
