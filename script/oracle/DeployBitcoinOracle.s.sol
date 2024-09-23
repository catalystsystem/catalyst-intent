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
        uint120 prismDeploymentBlockHeight,
        bytes32 prismDeploymentBlockHash,
        uint120 prismDeploymentBlockTime,
        bytes32 prismDeploymentExpectedTarget,
        bool isTestnet
    ) internal returns (BtcPrism btcPrism) {
        vm.startBroadcast();

        // TODO: set correct header & block height.
        btcPrism = new BtcPrism{ salt: 0 }(
            prismDeploymentBlockHeight,
            prismDeploymentBlockHash,
            prismDeploymentBlockTime,
            uint256(prismDeploymentExpectedTarget),
            isTestnet
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
        BitcoinOracle bitcoinOracle = new BitcoinOracle{ salt: bytes32(0) }(address(0), escrow, bitcoinPrimsm);
        vm.stopBroadcast();

        return bitcoinOracle;
    }

    function deploy(
        string memory chainName
    ) public returns (BitcoinOracle) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/oracle/bitcoin-info.json");
        string memory json = vm.readFile(path);
        bytes memory chainDataParsed = stdJson.parseRaw(json, string.concat(".", chainName));
        BitcoinChain memory bitcoinChain = abi.decode(chainDataParsed, (BitcoinChain));
        address escrowAddress = bitcoinChain.escrow;

        //TODO: change config with escrows addresses
        if (escrowAddress == address(0)) {
            IIncentivizedMessageEscrow escrow =
                new IncentivizedMockEscrow(address(uint160(0xdead)), bytes32(block.chainid), address(5), 0, 0);
            escrowAddress = address(escrow);
        }
        bitcoinChain.escrow = escrowAddress;
        BtcPrism btcPrism = deployBitcoinPrism(
            bitcoinChain.prismDeploymentBlockHeight,
            bitcoinChain.prismDeploymentBlockHash,
            bitcoinChain.prismDeploymentBlockTime,
            bitcoinChain.prismDeploymentExpectedTarget,
            bitcoinChain.isTestnet
        );

        return deploy(escrowAddress, address(btcPrism));
    }
}
