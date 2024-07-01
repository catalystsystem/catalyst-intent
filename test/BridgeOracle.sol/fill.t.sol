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

    function test_fill_single(address sender, uint256 amount, address recipient) external {
        address token;
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
            token, abi.encodeWithSignature("transferFrom(address,address,uint256)", address(sender), recipient, amount)
        );

        vm.prank(sender);
        oracle.fill(outputs, fillTimes);

        // TODO: verify event

        bool status = oracle.isProven(output, fillTimes[0], bytes32(0));
        assertTrue(status);
    }

    function test_fill_single_modified_output(uint256 amount, address recipient) external {
        vm.assume(amount > 0);
        address token;
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

    function test_fill_single_modified_recipient(
        uint256 amount,
        address sentToRecipient,
        address actualRecipient
    ) external {
        vm.assume(sentToRecipient != actualRecipient);
        address token;
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

    struct AmountRecipient {
        uint256 amount;
        bytes32 recipient;
    }

    function test_fill_multiple_single_verify(AmountRecipient[] memory amountRecipient) external {
        address token;
        uint32[] memory fillTimes = new uint32[](amountRecipient.length);
        Output[] memory outputs = new Output[](amountRecipient.length);
        uint32 fillTime = uint32(block.timestamp);
        for (uint256 i; i < amountRecipient.length; ++i) {
            fillTimes[i] = fillTime;
            outputs[i] = Output({
                token: bytes32(abi.encode(token)),
                amount: amountRecipient[i].amount,
                recipient: amountRecipient[i].recipient,
                chainId: uint32(block.chainid)
            });
        }

        oracle.fill(outputs, fillTimes);

        for (uint256 i; i < outputs.length; ++i) {
            bool status = oracle.isProven(outputs[i], fillTime, bytes32(0));
            assertTrue(status);
        }
    }

    function test_fill_multiple_batch_verify(AmountRecipient[] memory amountRecipient) external {
        address token;
        uint32[] memory fillTimes = new uint32[](amountRecipient.length);
        Output[] memory outputs = new Output[](amountRecipient.length);
        uint32 fillTime = uint32(block.timestamp);
        for (uint256 i; i < amountRecipient.length; ++i) {
            fillTimes[i] = fillTime;
            outputs[i] = Output({
                token: bytes32(abi.encode(token)),
                amount: amountRecipient[i].amount,
                recipient: amountRecipient[i].recipient,
                chainId: uint32(block.chainid)
            });
        }

        oracle.fill(outputs, fillTimes);

        // Batch verify
        oracle.isProven(outputs, fillTime, bytes32(0));
    }

    function test_check_already_filled(address sender, uint256 amount, address recipient) external {
        address token; // TODO: Needs to be mocked with token.
        Output memory output = Output({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid)
        });
        Output[] memory outputs = new Output[](2);
        outputs[0] = output;
        outputs[1] = output;

        uint32[] memory fillTimes = new uint32[](2);
        fillTimes[0] = uint32(block.timestamp);
        fillTimes[1] = uint32(block.timestamp);

        vm.expectCall(
            token,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(sender), recipient, amount),
            1 // Exactly only 1 transfer to be made.
        );

        vm.prank(sender);
        oracle.fill(outputs, fillTimes);

        bool status = oracle.isProven(output, fillTimes[0], bytes32(0));
        assertTrue(status);
    }
}
