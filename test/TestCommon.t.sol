// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { ReactorLimitOrder } from "../src/reactors/ReactorLimitOrder.sol";

contract TestCommon is Test {
    ReactorLimitOrder reactor;

    // TODO:
    address constant PERMIT2 = address(uint160(1));

    function setUp() public virtual {
        // reactor = new ReactorLimitOrder(PERMIT2);
    }
}
