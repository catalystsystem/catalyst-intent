// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { Settler } from "../src/Settler.sol";

contract TestCommon is Test {

    Settler settler;

    bytes32 constant SOURCE_CHAIN = bytes32(uint256(123));
    address constant SEND_LOS_GAS_TO = address(uint160(0xdead));

    function setUp() virtual public {
        settler = new Settler(SOURCE_CHAIN, SEND_LOS_GAS_TO);
    }
}
