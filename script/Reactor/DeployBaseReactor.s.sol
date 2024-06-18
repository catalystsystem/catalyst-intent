// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { BaseReactor } from "../../src/reactors/BaseReactor.sol";
import { Script } from "forge-std/Script.sol";

//TODO: We can abstract the logic if we will end up with many reactors but leave it empty for now and use LimitOrderReactor
contract DeployBaseReactor is Script { }
