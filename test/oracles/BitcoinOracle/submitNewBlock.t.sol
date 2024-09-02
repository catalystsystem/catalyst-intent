// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import { DeployBitcoinOracle } from "../../../script/Oracle/DeployBitcoinOracle.sol";
import { OracleHelperConfig } from "../../../script/Oracle/HelperConfig.sol";
import { BtcPrism } from "bitcoinprism-evm/src/BtcPrism.sol";

contract TestBitcoinOracle is Test {
    BtcPrism prism;

    function setUp() public {
        DeployBitcoinOracle deployer = new DeployBitcoinOracle();
        (, OracleHelperConfig helperConfig) = deployer.run();
        (,,, address prismAddress,) = helperConfig.currentConfig();
        prism = BtcPrism(prismAddress);
    }

    function test_submit_new_block() public {
        // prism.submit(
        //     858_616,
        //     "0000fc2ad11d24df427f64f0247bf960258fe2f5e13576dc56ca000000000000000000005ba9740466fb42e86b282a8c7963db417229ae45a8e6b47740a1fb949ca376787a8bcd66763d0317623a9313"
        // );
    }
}
