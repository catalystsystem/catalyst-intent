// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Test } from "forge-std/Test.sol";

import { AddressType as ScriptAddressType, BitcoinAddress } from "bitcoinprism-evm/src/library/BtcScript.sol";
import { BtcScript } from "bitcoinprism-evm/src/library/BtcScript.sol";
import "bitcoinprism-evm/src/library/BitcoinOpcodes.sol";

contract TestBitcoinScript is Test {
    function test_script_from_BTCAddress() public {
        bytes32 pHash = hex"ae2f3d4b06579b62574d6178c10c882b91503740";
        BitcoinAddress memory btcAddress = BitcoinAddress(ScriptAddressType.P2PKH, pHash);

        bytes memory actualScript =
            bytes.concat(OP_DUB, OP_HASH160, PUSH_20, bytes20(pHash), OP_EQUALVERIFY, OP_CHECKSIG);
        bytes memory expectedScript = this.getScript(btcAddress);

        assertEq(keccak256(actualScript), keccak256(expectedScript));
    }

    function getScript(BitcoinAddress calldata btcAddress) external pure returns (bytes memory) {
        return BtcScript.getBitcoinScript(btcAddress);
    }
}
