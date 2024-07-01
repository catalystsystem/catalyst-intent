// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;


import "forge-std/Test.sol";

import { Output } from "../../src/interfaces/ISettlementContract.sol";
import { GeneralisedIncentivesOracle } from "../../src/oracles/BridgeOracle.sol";

/**
 * @dev Oracles are also fillers
 */
contract TestBridgeOracle is Test {

    GeneralisedIncentivesOracle oracle;

    function setUp() external {
        address escrow = address(0);
        oracle = new GeneralisedIncentivesOracle(escrow);

        // TODO: mock with ERC20.
    }

    function test_fill_single(address sender, address token, uint256 amount, address recipient) external {
        vm.assume(uint160(token) > 16);
        vm.assume(token != address(oracle));
        vm.assume(token != address(this));
        Output memory output = Output({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid)
        });
        Output[] memory outputs = new Output[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        fillTimes[0] = uint32(block.timestamp);

        vm.expectCall(
            token,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(sender), recipient, amount)
        );

        vm.prank(sender);
        oracle.fill(outputs, fillTimes);

        // TODO: verify event

        bool status = oracle.isProven(output, fillTimes[0], bytes32(0));
        assertTrue(status);
    }

    function test_fill_single_modified_output(address token, uint256 amount, address recipient) external {
        vm.assume(uint160(token) > 16);
        vm.assume(token != address(oracle));
        vm.assume(token != address(this));
        vm.assume(amount > 0);
        Output memory output = Output({
            token: bytes32(abi.encode(token)),
            amount: amount - 1,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid)
        });
        Output[] memory outputs = new Output[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        fillTimes[0] = uint32(block.timestamp);

        oracle.fill(outputs, fillTimes);

        output.amount = amount;

        bool status = oracle.isProven(output, fillTimes[0], bytes32(0));
        assertFalse(status);
    }

    function test_fill_single_modified_recipient(address token, uint256 amount, address sentToRecipient, address actualRecipient) external {
        vm.assume(uint160(token) > 16);
        vm.assume(token != address(oracle));
        vm.assume(token != address(this));
        Output memory output = Output({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(sentToRecipient)),
            chainId: uint32(block.chainid)
        });
        Output[] memory outputs = new Output[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        fillTimes[0] = uint32(block.timestamp);

        oracle.fill(outputs, fillTimes);

        output.recipient = bytes32(abi.encode(actualRecipient));

        bool status = oracle.isProven(output, fillTimes[0], bytes32(0));
        assertFalse(status);
    }

    // function test_multiple_single(Output[] calldata outputs) external {
    //     uint32[] memory fillTimes = new uint32[](outputs.length);
    //     for (uint256 i; i < outputs.length; ++i) {
    //         fillTimes[i] = uint32(block.timestamp);
    //     }

    //     oracle.fill(outputs, fillTimes);

    //     // TODO: 
    // }
}
