// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { MockERC20 } from "../../test/mocks/MockERC20.sol";
import { Script } from "forge-std/Script.sol";
import { DeployPermit2 } from "permit2/test/utils/DeployPermit2.sol";

interface Permit2DomainSeparator {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract ReactorHelperConfig is Script, DeployPermit2 {
    NetworkConfig public currentConfig;

    // We can also add the domain seprator here.
    struct NetworkConfig {
        //TODO: Possible to make it array in the future;
        address tokenToSwap;
        address permit2;
        uint256 deployerKey;
    }

    // Default ANVIL KEY
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
            tokenToSwap: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, //WETH address on sepolia
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3, //Permit2 multichain address
            deployerKey: vm.envUint("PK")
        });
    }

    function _getAnvilConfig() internal returns (NetworkConfig memory anvilConfig) {
        if (currentConfig.tokenToSwap != address(0)) return currentConfig;
        vm.startBroadcast();
        MockERC20 mockERC20 = new MockERC20("TestToken", "TT", 18);
        address permit2 = deployPermit2();
        vm.stopBroadcast();

        anvilConfig =
            NetworkConfig({ tokenToSwap: address(mockERC20), permit2: permit2, deployerKey: ANVIL_PRIVATE_KEY });
    }
}
