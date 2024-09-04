// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { BitcoinOracle } from "../../src/oracles/BitcoinOracle.sol";
import { BtcPrism } from "bitcoinprism-evm/src/BtcPrism.sol";
import { Script } from "forge-std/Script.sol";

contract DeployBitcoinOracle is Script {
    function deployBitcoinPrism() internal returns (BtcPrism btcPrism) {
        vm.startBroadcast();

        // TODO: set correct header & block height.
        btcPrism = new BtcPrism{ salt: 0 }(
            2902384,
            0x000000000000000f10b5de36d015586d3bf3f63a0faa418b73cb91aaff5de064,
            1725015258,
            0x0000000000000000000fffc00000000000000000000000000000000000000000,
            true
        );
        vm.stopBroadcast();
    }

    function iterBlock(uint256 height, bytes calldata header) external {
        vm.startBroadcast();

        BtcPrism(0xf0bdB16eEa70C049399993E6285E20E212010568).submit(height, header);

        vm.stopBroadcast();
    }

    function deploy(address escrow, address bitcoinPrimsm) public returns (BitcoinOracle) {
        vm.startBroadcast();
        BitcoinOracle bitcoinOracle = new BitcoinOracle{ salt: bytes32(0) }(escrow, bitcoinPrimsm);
        vm.stopBroadcast();

        return bitcoinOracle;
    }

    function deploy(address escrow) public returns (BitcoinOracle) {
        BtcPrism btcPrism = deployBitcoinPrism();

        return deploy(escrow, address(btcPrism));
    }
}
