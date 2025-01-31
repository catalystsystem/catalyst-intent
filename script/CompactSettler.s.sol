// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CatalystCompactSettlerWithDeposit } from "../src/reactors/settler/compact/CatalystCompactSettlerWithDeposit.sol";
import { Script } from "forge-std/Script.sol";

contract DeploytCompactWithDeposit is Script {
    address constant THE_COMPACT = address(0);

    function run() external {
        vm.broadcast();
        address compactSettler = address(new CatalystCompactSettlerWithDeposit(THE_COMPACT));
    }
}