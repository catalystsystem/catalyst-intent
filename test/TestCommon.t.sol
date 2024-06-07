// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { LimitOrderReactor } from "../src/reactors/LimitOrderReactor.sol";

contract TestCommon is Test {
    LimitOrderReactor reactor;

    // TODO:
    address constant PERMIT2 = address(uint160(1));

    function setUp() public virtual {
        // reactor = new LimitOrderReactor(PERMIT2);
    }

    function test() external pure { }
}
