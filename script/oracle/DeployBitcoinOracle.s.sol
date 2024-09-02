// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { BtcPrism } from "bitcoinprism-evm/src/BtcPrism.sol";
import { BitcoinOracle } from "../../src/oracles/BitcoinOracle.sol";
import { Script } from "forge-std/Script.sol";

contract DeployBitcoinOracle is Script {

    uint256 deployerKey;

    function deployBitcoinPrism() internal returns(BtcPrism btcPrism) {
        vm.startBroadcast(deployerKey);
         
        // TODO: set correct header & block height.
        btcPrism = new BtcPrism(
            2901673,
            hex"000000000000001afb1579543f6c2f5a100a80da68bf55ec28a368bdc3edeb0a",
            1356110045,
            0x000000000000000000000000000000000000000000000, // Needs to be set for mainnet.
            true
        );
        vm.stopBroadcast();
    }

    function deploy(address escrow, address bitcoinPrimsm) public returns (BitcoinOracle) {
        vm.startBroadcast(deployerKey);
        BitcoinOracle bitcoinOracle = new BitcoinOracle{ salt: bytes32(0) }(escrow, bitcoinPrimsm);
        vm.stopBroadcast();

        return bitcoinOracle;
    }

    function deploy(address escrow) public returns(BitcoinOracle) {
        BtcPrism btcPrism = deployBitcoinPrism();

        return deploy(escrow, address(btcPrism));
    }
}
