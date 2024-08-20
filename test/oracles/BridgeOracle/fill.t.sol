// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { OutputDescription } from "../../../src/interfaces/Structs.sol";
import { GeneralisedIncentivesOracle } from "../../../src/oracles/BridgeOracle.sol";
import { TestCommonGARP } from "../TestCommonGARP.sol";

/**
 * @dev Oracles are also fillers
 */
contract TestBridgeOracle is TestCommonGARP {
    uint256 constant MAX_FUTURE_FILL_TIME = 7 days;

    GeneralisedIncentivesOracle oracle;

    function setUp() external {
        oracle = new GeneralisedIncentivesOracle(address(escrow));

        // TODO: mock with ERC20.
    }

    function test_fill_single(address sender, uint256 amount, address recipient) external {
        address token;
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        fillTimes[0] = uint32(block.timestamp);

        vm.expectCall(
            token, abi.encodeWithSignature("transferFrom(address,address,uint256)", address(sender), recipient, amount)
        );

        vm.prank(sender);
        oracle.fill(outputs, fillTimes);

        // TODO: verify event

        bool status = oracle.isProven(output, fillTimes[0]);
        assertTrue(status);
    }

    function test_fill_single_only_approve_single_not_multiple(
        address sender,
        uint256 amount,
        address recipient
    ) external {
        vm.assume(amount < type(uint256).max);
        address token;
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        uint32 fillTime = uint32(block.timestamp);
        fillTimes[0] = fillTime;

        vm.prank(sender);
        oracle.fill(outputs, fillTimes);

        OutputDescription memory extraOutput = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount + 1,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });
        outputs = new OutputDescription[](2);
        outputs[0] = output;
        outputs[1] = extraOutput;

        bool status = oracle.isProven(outputs, fillTime);
        assertFalse(status);
    }

    function test_fill_only_for_timestamp(address sender, uint256 amount, address recipient) external {
        vm.assume(amount < type(uint256).max);
        address token;
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });
        OutputDescription memory secondOutput = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount + 1,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        uint32 fillTime = uint32(block.timestamp);
        fillTimes[0] = fillTime;

        // Fill the first output at time A.
        vm.prank(sender);
        oracle.fill(outputs, fillTimes);

        outputs[0] = secondOutput;
        fillTimes[0] = fillTime + 1;

        // THen fill the second output at time B.
        vm.prank(sender);
        oracle.fill(outputs, fillTimes);

        // Now lets try to verify both outputs using time A.

        outputs = new OutputDescription[](2);
        outputs[0] = output;
        outputs[1] = secondOutput;

        bool status = oracle.isProven(outputs, fillTime);
        assertFalse(status);
    }

    function test_fill_single_modified_output(uint256 amount, address recipient) external {
        vm.assume(amount > 0);
        address token;
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount - 1,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        fillTimes[0] = uint32(block.timestamp);

        oracle.fill(outputs, fillTimes);

        output.amount = amount;

        bool status = oracle.isProven(output, fillTimes[0]);
        assertFalse(status);
    }

    function test_fill_single_modified_recipient(
        uint256 amount,
        address sentToRecipient,
        address actualRecipient
    ) external {
        vm.assume(sentToRecipient != actualRecipient);
        address token;
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(sentToRecipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        fillTimes[0] = uint32(block.timestamp);

        oracle.fill(outputs, fillTimes);

        output.recipient = bytes32(abi.encode(actualRecipient));

        bool status = oracle.isProven(output, fillTimes[0]);
        assertFalse(status);
    }

    function test_revert_fill_time_in_past(
        uint24 fillTime,
        uint24 delta,
        address sender,
        uint256 amount,
        address recipient
    ) external {
        vm.warp(uint32(fillTime) + uint32(delta));

        address token;
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });

        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        fillTimes[0] = fillTime;

        if (delta != 0) vm.expectRevert(abi.encodeWithSignature("FillTimeInPast()"));

        vm.prank(sender);
        oracle.fill(outputs, fillTimes);
    }

    function test_revert_fill_time_in_far_future(
        uint32 fillTime,
        uint32 delta,
        address sender,
        address recipient,
        uint256 amount
    ) external {
        vm.warp(fillTime < delta ? 0 : fillTime - delta);

        address token;
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });

        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        fillTimes[0] = fillTime;

        if ((fillTime < delta ? fillTime : delta) > MAX_FUTURE_FILL_TIME) {
            vm.expectRevert(abi.encodeWithSignature("FillTimeFarInFuture()"));
        }

        vm.prank(sender);
        oracle.fill(outputs, fillTimes);
    }

    struct AmountRecipient {
        uint256 amount;
        bytes32 recipient;
    }

    function test_fill_multiple_single_verify(AmountRecipient[] memory amountRecipient) external {
        address token;
        uint32[] memory fillTimes = new uint32[](amountRecipient.length);
        OutputDescription[] memory outputs = new OutputDescription[](amountRecipient.length);
        uint32 fillTime = uint32(block.timestamp);
        for (uint256 i; i < amountRecipient.length; ++i) {
            fillTimes[i] = fillTime;
            outputs[i] = OutputDescription({
                token: bytes32(abi.encode(token)),
                amount: amountRecipient[i].amount,
                recipient: amountRecipient[i].recipient,
                chainId: uint32(block.chainid),
                remoteOracle: bytes32(0),
                remoteCall: hex""
            });
        }

        oracle.fill(outputs, fillTimes);

        for (uint256 i; i < outputs.length; ++i) {
            bool status = oracle.isProven(outputs[i], fillTime);
            assertTrue(status);
        }
    }

    function test_fill_multiple_batch_verify(AmountRecipient[] memory amountRecipient) external {
        address token;
        uint32[] memory fillTimes = new uint32[](amountRecipient.length);
        OutputDescription[] memory outputs = new OutputDescription[](amountRecipient.length);
        uint32 fillTime = uint32(block.timestamp);
        for (uint256 i; i < amountRecipient.length; ++i) {
            fillTimes[i] = fillTime;
            outputs[i] = OutputDescription({
                token: bytes32(abi.encode(token)),
                amount: amountRecipient[i].amount,
                recipient: amountRecipient[i].recipient,
                chainId: uint32(block.chainid),
                remoteOracle: bytes32(0),
                remoteCall: hex""
            });
        }

        oracle.fill(outputs, fillTimes);

        // Batch verify
        oracle.isProven(outputs, fillTime);
    }

    function test_check_already_filled(address sender, uint256 amount, address recipient) external {
        address token; // TODO: Needs to be mocked with token.
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });
        OutputDescription[] memory outputs = new OutputDescription[](2);
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

        bool status = oracle.isProven(output, fillTimes[0]);
        assertTrue(status);
    }

    function test_revert_fill_wrong_chain(uint32 chainId, address sender, uint256 amount, address recipient) external {
        vm.assume(uint32(block.chainid) != chainId);
        address token;
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: chainId,
            remoteOracle: bytes32(0),
            remoteCall: hex""
        });
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        fillTimes[0] = uint32(block.timestamp);

        vm.expectRevert(abi.encodeWithSignature("WrongChain()"));

        vm.prank(sender);
        oracle.fill(outputs, fillTimes);
    }
}
