// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { ReactorLimitOrder } from "../src/reactors/ReactorLimitOrder.sol";

contract TestCommon is Test {

    ReactorLimitOrder reactor;

    // TODO:
    address constant PERMIT2 = address(bytes160(1));

    function setUp() virtual public {
        reactor = new ReactorLimitOrder(PERMIT2);
    }
}
