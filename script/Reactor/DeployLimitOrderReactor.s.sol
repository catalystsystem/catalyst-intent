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
        LimitOrderReactor limitOrderReactor = new LimitOrderReactor{ salt: 0xda14c7b6c0505868af38164cf5c6248b2efec040619ccd9710b2ba17bd4b1595 }(PERMIT2, owner);
        vm.stopBroadcast();

        return limitOrderReactor;
    }

    function deploy() external returns (LimitOrderReactor) {
        return deploy(CATALYST_ADDRESS);
    }

    function initCodeHash() external view returns(bytes32) {
        return keccak256(abi.encodePacked(type(LimitOrderReactor).creationCode, abi.encode(PERMIT2, CATALYST_ADDRESS)));
    }
}
