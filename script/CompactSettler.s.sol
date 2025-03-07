// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Script } from "forge-std/Script.sol";
import { CompactSettlerWithDeposit } from "src/settlers/compact/CompactSettlerWithDeposit.sol";

contract DeployCompactSettler is Script {

    function deploy(address theCompact) external {
        vm.broadcast();
        address(new CompactSettlerWithDeposit{salt: bytes32(0)}(theCompact));
    }
}
