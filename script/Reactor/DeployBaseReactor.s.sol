// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { BaseReactor } from "../../src/reactors/BaseReactor.sol";
import { Script } from "forge-std/Script.sol";

// LimitOrderReactor
contract DeployBaseReactor is Script {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant CATALYST_ADDRESS = 0x0000000099263f0735D03bB2787cE8FB84f6ED6E;
    uint256 deployerKey = uint256(0);
}
