// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { GARPBitcoinOracle } from "../../src/oracles/GARP/GARPBitcoinOracle.sol";
import { BitcoinOracle } from "../../src/oracles/BitcoinOracle.sol";

import { BtcPrism } from "bitcoinprism-evm/src/BtcPrism.sol";
import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

contract DeployBitcoinOracle is Script {
    struct BitcoinChain {
        address escrow;
        bool isTestnet;
        bytes32 prismDeploymentBlockHash;
        uint120 prismDeploymentBlockHeight;
        uint120 prismDeploymentBlockTime;
        bytes32 prismDeploymentExpectedTarget;
    }

    function deployBitcoinPrism(
        uint120 blockHeight,
        bytes32 blockHash,
        uint120 blockTime,
        bytes32 expectedTarget,
        bool isTestnet
    ) internal returns (BtcPrism btcPrism) {
        vm.startBroadcast();

        btcPrism = new BtcPrism{ salt: 0 }(blockHeight, blockHash, blockTime, uint256(expectedTarget), isTestnet);
        vm.stopBroadcast();
    }

    function deployGarped(address escrow, address bitcoinPrism) public returns (GARPBitcoinOracle) {
        return deployGarped(escrow, bitcoinPrism, address(0));
    }

    function deployGarped(address escrow, address bitcoinPrism, address owner) public returns (GARPBitcoinOracle) {
        vm.startBroadcast();
        GARPBitcoinOracle bitcoinOracle = new GARPBitcoinOracle{ salt: bytes32(0) }(owner, escrow, bitcoinPrism);
        vm.stopBroadcast();

        return bitcoinOracle;
    }

    function deploy(address bitcoinPrism) public returns (BitcoinOracle) {
        vm.startBroadcast();
        BitcoinOracle bitcoinOracle = new BitcoinOracle{ salt: bytes32(0x22694c56b29a7d25cbc6dddf3e97a712f46cca66f4d932f2a5afb4c830ac87bd) }(bitcoinPrism);
        vm.stopBroadcast();

        return bitcoinOracle;
    }

    function initCodeHashBitcoin() external pure returns(bytes32) {
        return keccak256(abi.encodePacked(type(BitcoinOracle).creationCode, abi.encode(address(0x00000000fA2e1B15E3fa9a8aad01605355d98F0f))));
    }

    //--- Prism helpers ---//

    function iterBlock(address prism, uint256 height, bytes calldata header) external {
        vm.startBroadcast();

        BtcPrism(prism).submit(height, header);

        vm.stopBroadcast();
    }
}
