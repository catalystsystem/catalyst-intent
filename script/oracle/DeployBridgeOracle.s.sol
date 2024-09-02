// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { BridgeOracle } from "../../src/oracles/BridgeOracle.sol";
import { Script } from "forge-std/Script.sol";

contract DeployBridgeOracle is Script {
    uint256 deployerKey;

    function deploy(address escrow) public returns (BridgeOracle) {
        vm.startBroadcast(deployerKey);
        BridgeOracle bridgeOracle = new BridgeOracle{ salt: bytes32(0) }(escrow);
        vm.stopBroadcast();

        return bridgeOracle;
    }

    // function deploy(address escrow) public returns(BridgeOracle) {
    //     BtcPrism btcPrism = deployBitcoinPrism();

    //     return deploy(escrow, address(btcPrism));
    // }
}
