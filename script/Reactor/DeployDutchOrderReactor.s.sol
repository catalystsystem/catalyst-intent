// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DutchOrderReactor } from "../../src/reactors/DutchOrderReactor.sol";
import { DeployBaseReactor } from "./DeployBaseReactor.s.sol";

contract DeployDutchOrderReactor is DeployBaseReactor {
    function deploy(
        address owner
    ) public returns (DutchOrderReactor) {
        if (deployerKey != 0) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }
        DutchOrderReactor dutchOrderReactor = new DutchOrderReactor{ salt: 0x000000000000000000000000000000000000000077900d21a8f41f01b4e89295 }(PERMIT2, owner);
        vm.stopBroadcast();

        return dutchOrderReactor;
    }

    function deploy() external returns (DutchOrderReactor) {
        return deploy(CATALYST_ADDRESS);
    }

    function initCodeHash() external pure returns(bytes32) {
        return keccak256(abi.encodePacked(type(DutchOrderReactor).creationCode, abi.encode(PERMIT2, CATALYST_ADDRESS)));
    }
        
}
