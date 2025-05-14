// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { CoinFiller } from "src/fillers/coin/CoinFiller.sol";
import { OutputDescription } from "src/libs/OutputEncodingLib.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";

contract CoinFillerTestFillBatch is Test {
    error FilledBySomeoneElse(bytes32 solver);

    event OutputFilled(bytes32 indexed orderId, bytes32 solver, uint32 timestamp, OutputDescription output);

    CoinFiller coinFiller;

    MockERC20 outputToken;

    address swapper;
    address coinFillerAddress;
    address outputTokenAddress;

    function setUp() public {
        coinFiller = new CoinFiller();
        outputToken = new MockERC20("TEST", "TEST", 18);

        swapper = makeAddr("swapper");
        coinFillerAddress = address(coinFiller);
        outputTokenAddress = address(outputToken);
    }

    /// forge-config: default.isolate = true
    function test_fill_batch_gas() external {
        test_fill_batch(keccak256(bytes("orderId")), makeAddr("sender"), keccak256(bytes("filler")), keccak256(bytes("nextFiller")), 10**18, 10**12);
    }

    function test_fill_batch(
        bytes32 orderId,
        address sender,
        bytes32 filler,
        bytes32 nextFiller,
        uint128 amount,
        uint128 amount2
    ) public {
        vm.assume(
            filler != bytes32(0) && swapper != sender && nextFiller != filler && nextFiller != bytes32(0)
                && amount != amount2
        );

        outputToken.mint(sender, uint256(amount) + uint256(amount2));
        vm.prank(sender);
        outputToken.approve(coinFillerAddress, uint256(amount) + uint256(amount2));

        OutputDescription[] memory outputs = new OutputDescription[](2);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(coinFillerAddress))),
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(outputTokenAddress))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        outputs[1] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(coinFillerAddress))),
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(outputTokenAddress))),
            amount: amount2,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        vm.expectEmit();
        emit OutputFilled(orderId, filler, uint32(block.timestamp), outputs[0]);
        emit OutputFilled(orderId, filler, uint32(block.timestamp), outputs[1]);

        vm.expectCall(
            outputTokenAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, swapper, amount)
        );
        vm.expectCall(
            outputTokenAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, swapper, amount2)
        );

        uint256 prefillSnapshot = vm.snapshot();

        vm.prank(sender);
        coinFiller.fillBatch(type(uint32).max, orderId, outputs, filler);
        vm.snapshotGasLastCall("filler", "coinFillerFillBatch");

        assertEq(outputToken.balanceOf(swapper), uint256(amount) + uint256(amount2));
        assertEq(outputToken.balanceOf(sender), 0);

        vm.revertTo(prefillSnapshot);
        // Fill the first output by someone else. The other outputs won't be filled.
        vm.prank(sender);
        coinFiller.fill(type(uint32).max, orderId, outputs[0], nextFiller);

        vm.expectRevert(abi.encodeWithSignature("FilledBySomeoneElse(bytes32)", (nextFiller)));
        vm.prank(sender);
        coinFiller.fillBatch(type(uint32).max, orderId, outputs, filler);

        vm.revertTo(prefillSnapshot);
        // Fill the second output by someone else. The first output will be filled.

        vm.prank(sender);
        coinFiller.fill(type(uint32).max, orderId, outputs[1], nextFiller);

        vm.prank(sender);
        coinFiller.fillBatch(type(uint32).max, orderId, outputs, filler);
    }

    function test_revert_fill_batch_fillDeadline(
        uint24 fillDeadline,
        uint24 excess
    ) public {
        bytes32 orderId = keccak256(bytes("orderId"));
        address sender = makeAddr("sender");
        bytes32 filler = keccak256(bytes("filler"));
        uint128 amount = 10**18;


        outputToken.mint(sender, uint256(amount));
        vm.prank(sender);
        outputToken.approve(coinFillerAddress, uint256(amount));

        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(coinFillerAddress))),
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(outputTokenAddress))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        uint32 warpTo = uint32(excess) + uint32(fillDeadline);
        vm.warp(warpTo);

        if (excess != 0) vm.expectRevert(abi.encodeWithSignature("FillDeadline()"));
        vm.prank(sender);
        coinFiller.fillBatch(fillDeadline, orderId, outputs, filler);
    }
}
