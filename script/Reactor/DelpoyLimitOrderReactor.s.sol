// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { LimitOrderReactor } from "../../src/reactors/LimitOrderReactor.sol";
import { ReactorHelperConfig } from "./HelperConfig.sol";
import { Script } from "forge-std/Script.sol";

contract DeployLimitOrderReactor is Script {
    function run() external returns (LimitOrderReactor, ReactorHelperConfig) {
        ReactorHelperConfig helperConfig = new ReactorHelperConfig();
        (,, address permit2, uint256 deployerKey) = helperConfig.currentConfig();
        vm.startBroadcast(deployerKey);
        LimitOrderReactor limitOrderReactor = new LimitOrderReactor(permit2);
        vm.stopBroadcast();

        return (limitOrderReactor, helperConfig);
    }
}
