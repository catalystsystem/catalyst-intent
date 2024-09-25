// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { BitcoinOracle } from "../../src/oracles/BitcoinOracle.sol";

import { IncentivizedMockEscrow } from "GeneralisedIncentives/apps/mock/IncentivizedMockEscrow.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";

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

        btcPrism = new BtcPrism{ salt: 0 }(
            blockHeight,
            blockHash,
            blockTime,
            uint256(expectedTarget),
            isTestnet
        );
        vm.stopBroadcast();
    }

    function deploy(address escrow, address bitcoinPrism) public returns (BitcoinOracle) {
        return deploy(escrow, bitcoinPrism, address(0));
    }

     function deploy(address escrow, address bitcoinPrism, address owner) public returns (BitcoinOracle) {
        vm.startBroadcast();
        BitcoinOracle bitcoinOracle = new BitcoinOracle{ salt: bytes32(0) }(owner, escrow, bitcoinPrism);
        vm.stopBroadcast();

        return bitcoinOracle;
    }

    //--- Prism helpers ---//

    function iterBlock(address prism, uint256 height, bytes calldata header) external {
        vm.startBroadcast();

        BtcPrism(prism).submit(height, header);

        vm.stopBroadcast();
    }
}
