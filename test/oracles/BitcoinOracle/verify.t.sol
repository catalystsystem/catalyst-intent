// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DeployBitcoinOracle } from "../../../script/oracle/DeployBitcoinOracle.s.sol";
import { BitcoinOracle } from "../../../src/oracles/BitcoinOracle.sol";
import { Test } from "forge-std/Test.sol";

contract TestBitcoinOracle is Test {
    BitcoinOracle bitcoinOracle;
    DeployBitcoinOracle deployBitcoinOracle = new DeployBitcoinOracle();

    function setUp() public {
        bitcoinOracle = deployBitcoinOracle.deploy();
    }

    function testA() public { }
}
