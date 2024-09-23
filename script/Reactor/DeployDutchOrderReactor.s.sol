// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DutchOrderReactor } from "../../src/reactors/DutchOrderReactor.sol";
import { DeployBaseReactor } from "./DeployBaseReactor.s.sol";
import { ReactorHelperConfig } from "./HelperConfig.s.sol";

contract DeployDutchOrderReactor is DeployBaseReactor {
    function deploy(
        address owner
    ) public returns (DutchOrderReactor) {
        if (deployerKey != 0) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }
        DutchOrderReactor dutchOrderReactor = new DutchOrderReactor{ salt: bytes32(0) }(PERMIT2, owner);
        vm.stopBroadcast();

        return dutchOrderReactor;
    }

    function deploy() external returns (DutchOrderReactor) {
        return deploy(CATALYST_ADDRESS);
    }
}
