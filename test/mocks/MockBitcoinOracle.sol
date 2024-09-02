// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { BitcoinOracle } from "../../src/oracles/BitcoinOracle.sol";
import { BtcProof, BtcTxProof } from "bitcoinprism-evm/src/library/BtcProof.sol";

import { OutputDescription } from "../../src/interfaces/Structs.sol";
import { IBtcPrism } from "bitcoinprism-evm/src/interfaces/IBtcPrism.sol";

contract MockBitcoinOracle is BitcoinOracle {
    constructor(address _escrow, IBtcPrism _mirror) BitcoinOracle(_escrow, _mirror) { }
}
