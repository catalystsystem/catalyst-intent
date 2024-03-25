// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { Reactor } from "../src/Reactor.sol";

contract TestCommon is Test {

    Reactor reactor;

    bytes32 constant SOURCE_CHAIN = bytes32(uint256(123));
    address constant SEND_LOS_GAS_TO = address(uint160(0xdead));

    function setUp() virtual public {
        reactor = new Reactor(SOURCE_CHAIN, SEND_LOS_GAS_TO);
    }
}
