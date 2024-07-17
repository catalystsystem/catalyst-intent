// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DutchOrderReactor } from "../../src/reactors/DutchOrderReactor.sol";
import { ReactorHelperConfig } from "./HelperConfig.s.sol";
import { Script } from "forge-std/Script.sol";

contract DeployDutchOrderReactor is Script {
    function run() external returns (DutchOrderReactor, ReactorHelperConfig) {
        ReactorHelperConfig helperConfig = new ReactorHelperConfig();
        (,, address permit2, uint256 deployerKey) = helperConfig.currentConfig();
        vm.startBroadcast(deployerKey);
        DutchOrderReactor dutchOrderReactor = new DutchOrderReactor{ salt: bytes32(0) }(permit2);
        vm.stopBroadcast();

        return (dutchOrderReactor, helperConfig);
    }
}
