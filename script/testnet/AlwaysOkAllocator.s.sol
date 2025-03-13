// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Script } from "forge-std/Script.sol";
import { AlwaysOKAllocator } from "lib/the-compact/src/test/AlwaysOKAllocator.sol";
import { AlwaysYesOracle } from "test/mocks/AlwaysYesOracle.sol";

contract DeployAllocator is Script {

    function deploy() external {
        vm.broadcast();
        address(new AlwaysOKAllocator{salt: bytes32(0)}());
    }

    function deployOracle() external {
        vm.broadcast();
        address(new AlwaysYesOracle{salt: bytes32(0)}());
    }
}
