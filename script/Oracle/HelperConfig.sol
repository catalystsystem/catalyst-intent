// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { MockERC20 } from "../../test/mocks/MockERC20.sol";

import { IncentivizedMockEscrow } from "GeneralisedIncentives/apps/mock/IncentivizedMockEscrow.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";

import { BtcPrism } from "bitcoinprism-evm/src/BtcPrism.sol";
import { Script } from "forge-std/Script.sol";

import "../../test/oracles/BitcoinOracle/blockInfo.t.sol";

contract OracleHelperConfig is Script {
    NetworkConfig public currentConfig;

    struct NetworkConfig {
        address tokenToSwapInput;
        address tokenToSwapOutput;
        address escrow;
        address prismAddress;
        uint256 deployerKey;
    }

    uint256 public ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11_155_111) {
            currentConfig = _getSepoliaConfig();
        } else {
            currentConfig = _getAnvilConfig();
        }
    }

    function _getSepoliaConfig() internal view returns (NetworkConfig memory sepoliaConfig) {
        sepoliaConfig = NetworkConfig({
            tokenToSwapInput: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, //WETH address on sepolia
            tokenToSwapOutput: 0x61EDCDf5bb737ADffE5043706e7C5bb1f1a56eEA, //BETH address on sepolia
            escrow: address(0),
            prismAddress: address(0),
            deployerKey: vm.envUint("PK")
        });
    }

    function _getAnvilConfig() internal returns (NetworkConfig memory anvilConfig) {
        if (currentConfig.tokenToSwapInput != address(0)) return currentConfig;
        vm.startBroadcast();

        MockERC20 input = new MockERC20("TestTokenInput", "TTI", 18);
        MockERC20 output = new MockERC20("TestTokenOutput", "ERC", 18);

        IIncentivizedMessageEscrow escrow =
            new IncentivizedMockEscrow(address(uint160(0xdead)), bytes32(block.chainid), address(5), 0, 0);

        BtcPrism prism = new BtcPrism(BLOCK_HEIGHT, BLOCK_HASH, BLOCK_TIME, EXPECTED_TARGET, false);

        vm.stopBroadcast();

        anvilConfig = NetworkConfig({
            tokenToSwapInput: address(input),
            tokenToSwapOutput: address(output),
            escrow: address(escrow),
            prismAddress: address(prism),
            deployerKey: ANVIL_PRIVATE_KEY
        });
    }
}
