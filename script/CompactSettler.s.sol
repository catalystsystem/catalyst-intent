// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CompactSettlerWithDeposit } from "src/settlers/compact/CompactSettlerWithDeposit.sol";
import { Script } from "forge-std/Script.sol";

contract DeploytCompactWithDeposit is Script {
    address constant THE_COMPACT = address(0);

    function run() external {
        vm.broadcast();
        address compactSettler = address(new CompactSettlerWithDeposit(THE_COMPACT));
    }
}