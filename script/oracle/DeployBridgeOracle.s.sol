// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { GARPBridgeOracle } from "../../src/oracles/GARP/GARPBridgeOracle.sol";
import { Script } from "forge-std/Script.sol";

contract DeployBridgeOracle is Script {
    uint256 deployerKey;

    function deploy(
        address escrow
    ) public returns (GARPBridgeOracle) {
        vm.startBroadcast(deployerKey);
        address deployerAddress = vm.addr(deployerKey);
        GARPBridgeOracle bridgeOracle = new GARPBridgeOracle{ salt: bytes32(0) }(deployerAddress, escrow);
        vm.stopBroadcast();

        return bridgeOracle;
    }
}
