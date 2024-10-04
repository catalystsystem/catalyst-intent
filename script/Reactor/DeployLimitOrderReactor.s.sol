// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { LimitOrderReactor } from "../../src/reactors/LimitOrderReactor.sol";
import { DeployBaseReactor } from "./DeployBaseReactor.s.sol";

contract DeployLimitOrderReactor is DeployBaseReactor {
    function deploy(
        address owner
    ) public returns (LimitOrderReactor) {
        if (deployerKey != 0) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }
        LimitOrderReactor limitOrderReactor = new LimitOrderReactor{ salt: bytes32(0) }(PERMIT2, owner);
        vm.stopBroadcast();

        return limitOrderReactor;
    }

    function deploy() external returns (LimitOrderReactor) {
        return deploy(CATALYST_ADDRESS);
    }
}
