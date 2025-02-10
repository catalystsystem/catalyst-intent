// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { CoinFiller } from "../../../src/fillers/coin/CoinFiller.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { OutputDescription } from "../../../src/libs/OutputEncodingLib.sol";
import { MockCallbackExecutor } from "../../mocks/MockCallbackExecutor.sol";

contract TestCoinFiller is Test {
    error ZeroValue();  
    error WrongChain(uint256 expected, uint256 actual);
    error WrongRemoteFiller(bytes32 addressThis, bytes32 expected);
    error FilledBySomeoneElse(bytes32 solver);
    error NotImplemented();
    error SlopeStopped();

    event OutputFilled(bytes32 orderId, bytes32 solver, uint32 timestamp, OutputDescription output);

    CoinFiller coinFiller;

    MockERC20 outputToken;
    MockCallbackExecutor mockCallbackExecutor;

    address swapper;
    address coinFillerAddress;
    address outputTokenAddress;
    address mockCallbackExecutorAddress;

    function setUp() public {
        coinFiller = new CoinFiller();
        outputToken = new MockERC20("TEST", "TEST", 18);
        mockCallbackExecutor = new MockCallbackExecutor();

        swapper = makeAddr("swapper");
        coinFillerAddress  = address(coinFiller);
        outputTokenAddress = address(outputToken);
        mockCallbackExecutorAddress = address(mockCallbackExecutor);
    }

    // --- VALID CASES --- //

    function test_fill_skip(bytes32 orderId, address sender, bytes32 filler, uint256 amount) public {
        vm.assume(filler != bytes32(0) && swapper != sender);

        outputToken.mint(sender, amount);
        vm.prank(sender);
        outputToken.approve(coinFillerAddress, amount);

        bytes32[] memory  orderIds = new bytes32[](1);
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
        orderIds[0] = orderId;
        
        vm.prank(sender);

        vm.expectEmit();
        emit OutputFilled(orderId, filler, uint32(block.timestamp), outputs[0]);

        vm.expectCall(
            outputTokenAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, swapper, amount)
        );

        coinFiller.fillSkip(orderIds, outputs, filler);

        assertEq(outputToken.balanceOf(swapper), amount);
        assertEq(outputToken.balanceOf(sender), 0);
    }

    function test_fill_throw(bytes32 orderId, address sender, bytes32 filler, uint256 amount) public {
        vm.assume(filler != bytes32(0) && swapper != sender);

        outputToken.mint(sender, amount);
        vm.prank(sender);
        outputToken.approve(coinFillerAddress, amount);

        bytes32[] memory  orderIds = new bytes32[](1);
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
        orderIds[0] = orderId;
        
        vm.prank(sender);
        vm.expectEmit();
        emit OutputFilled(orderId, filler, uint32(block.timestamp), outputs[0]);

        vm.expectCall(
            outputTokenAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, swapper, amount)
        );

        coinFiller.fillThrow(orderIds, outputs, filler);

        assertEq(outputToken.balanceOf(swapper), amount);
        assertEq(outputToken.balanceOf(sender), 0);
    }

    function test_mock_callback_executor(address sender, bytes32 orderId, uint256 amount, bytes32 filler, bytes memory remoteCallData) public {
        vm.assume(filler != bytes32(0));
        vm.assume(sender != mockCallbackExecutorAddress);
        vm.assume(remoteCallData.length != 0);

        outputToken.mint(sender, amount);
        vm.prank(sender);
        outputToken.approve(coinFillerAddress, amount);

        OutputDescription[] memory outputs = new OutputDescription[](1);
        
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(coinFillerAddress))),
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(outputTokenAddress))),
            amount: amount,
            recipient: bytes32(uint256(uint160(mockCallbackExecutorAddress))),
            remoteCall: remoteCallData,
            fulfillmentContext: bytes("")
        });
        
        vm.prank(sender);
        vm.expectCall(
            mockCallbackExecutorAddress,
            abi.encodeWithSignature("outputFilled(bytes32,uint256,bytes)", outputs[0].token, outputs[0].amount, remoteCallData)
        );
        vm.expectCall(
            outputTokenAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, mockCallbackExecutorAddress, amount)
        );

        vm.expectEmit();
        emit OutputFilled(orderId, filler, uint32(block.timestamp), outputs[0]);

        coinFiller.fill(orderId, outputs[0], filler);

        assertEq(outputToken.balanceOf(mockCallbackExecutorAddress), amount);
        assertEq(outputToken.balanceOf(sender), 0);
    }

    function test_dutch_auction(bytes32 orderId, address sender, bytes32 filler, uint256 amount, uint128 slope, uint128 stopTime) public {
        vm.assume(filler != bytes32(0) && swapper != sender);
        vm.assume(stopTime > block.timestamp);
        vm.assume(type(uint256).max - amount > slope * (stopTime - block.timestamp));

        outputToken.mint(sender, amount + slope * (stopTime - block.timestamp));
        vm.prank(sender);
        outputToken.approve(coinFillerAddress, amount + slope * (stopTime - block.timestamp));

        OutputDescription[] memory outputs = new OutputDescription[](1);
        
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(coinFillerAddress))),
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(outputTokenAddress))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: bytes(""),
            fulfillmentContext: abi.encodePacked(bytes1(0x01), bytes32(uint256(slope)), bytes32(uint256(stopTime)))
        });
        
        vm.prank(sender);

        vm.expectEmit();
        emit OutputFilled(orderId, filler, uint32(block.timestamp), outputs[0]);

        vm.expectCall(
            outputTokenAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, swapper, amount + slope * (stopTime - block.timestamp))
        );

        coinFiller.fill(orderId, outputs[0], filler);

        assertEq(outputToken.balanceOf(swapper), amount + slope * (stopTime - block.timestamp));
        assertEq(outputToken.balanceOf(sender), 0);
    }

    // --- FAILURE CASES --- //
    
    function test_fill_zero_filler(address sender, bytes32 orderId) public {
        bytes32[] memory  orderIds = new bytes32[](1);
        OutputDescription[] memory outputs = new OutputDescription[](1);
        bytes32 filler = bytes32(0);

        orderIds[0] = orderId;
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(0),
            remoteOracle: bytes32(0),
            chainId: 0,
            token: bytes32(0),
            amount: 0,
            recipient: bytes32(0),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        vm.expectRevert(ZeroValue.selector);
        vm.prank(sender);
        coinFiller.fill(orderId, outputs[0], filler);
    }

    function test_invalid_chain_id(address sender, bytes32 filler, bytes32 orderId, uint256 chainId) public {
        vm.assume(chainId != block.chainid);
        vm.assume(filler != bytes32(0));

        OutputDescription[] memory outputs = new OutputDescription[](1);

        outputs[0] = OutputDescription({
            remoteFiller: bytes32(0),
            remoteOracle: bytes32(0),
            chainId: chainId,
            token: bytes32(0),
            amount: 0,
            recipient: bytes32(0),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(WrongChain.selector, block.chainid, chainId));
        vm.prank(sender);
        coinFiller.fill(orderId, outputs[0], filler);
    }

    function test_invalid_filler(address sender, bytes32 filler, bytes32 orderId, bytes32 fillerOracleBytes) public {
        bytes32 coinFillerOracleBytes = bytes32(uint256(uint160(coinFillerAddress)));

        vm.assume(fillerOracleBytes != coinFillerOracleBytes);
        vm.assume(filler != bytes32(0));

        OutputDescription[] memory outputs = new OutputDescription[](1);

        outputs[0] = OutputDescription({
            remoteFiller: fillerOracleBytes,
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(0),
            amount: 0,
            recipient: bytes32(0),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(WrongRemoteFiller.selector, coinFillerOracleBytes, fillerOracleBytes));
        vm.prank(sender);
        coinFiller.fill(orderId, outputs[0], filler);
    }     

    function test_fill_made_already(address sender, bytes32 filler, bytes32 differentFiller, bytes32 orderId, uint256 amount) public {
        vm.assume(filler != bytes32(0));
        vm.assume(filler != differentFiller && differentFiller != bytes32(0));

        outputToken.mint(sender, amount);
        vm.prank(sender);
        outputToken.approve(coinFillerAddress, amount);

        bytes32[] memory  orderIds = new bytes32[](1);
        OutputDescription[] memory outputs = new OutputDescription[](1);

        orderIds[0] = orderId;
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(coinFillerAddress))),
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(outputTokenAddress))),
            amount: amount,
            recipient: bytes32(0),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        vm.prank(sender);
        coinFiller.fillThrow(orderIds, outputs, filler);
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(FilledBySomeoneElse.selector, filler));
        coinFiller.fillThrow(orderIds, outputs, differentFiller);
    }
    
    function test_call_with_real_address(address sender, uint256 amount) public {
        vm.assume(sender != address(0));

        OutputDescription memory output = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))), // TODO: 0?
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(outputTokenAddress))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });
        
        vm.prank(sender);
        vm.expectRevert();
        coinFiller.call(amount, output);
    }

    function test_invalid_fulfillment_context(address sender, bytes32 filler, bytes32 orderId, uint256 amount, bytes memory fulfillmentContext) public {
        vm.assume(fulfillmentContext.length != 65 && fulfillmentContext.length > 1);
        vm.assume(filler != bytes32(0));

        outputToken.mint(sender, amount);
        vm.prank(sender);
        outputToken.approve(coinFillerAddress, amount);

        OutputDescription[] memory outputs = new OutputDescription[](1);

        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(coinFillerAddress))),
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(outputTokenAddress))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: bytes(""),
            fulfillmentContext: fulfillmentContext
        });

        vm.prank(sender);
        vm.expectRevert(NotImplemented.selector);
        coinFiller.fill(orderId, outputs[0], filler);
    }

    function test_slope_stopped(address sender, bytes32 orderId, bytes32 filler, uint256 amount, uint256 slope, uint256 currentTime, uint256 stopTime) public {
        vm.assume(stopTime < currentTime);
        vm.warp(currentTime);
        vm.assume(filler != bytes32(0));

        OutputDescription[] memory outputs = new OutputDescription[](1);

        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(coinFillerAddress))),
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(outputTokenAddress))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: bytes(""),
            fulfillmentContext: abi.encodePacked(bytes1(0x01), bytes32(slope), bytes32(stopTime))
        });

        vm.prank(sender);
        vm.expectRevert(SlopeStopped.selector);
        coinFiller.fill(orderId, outputs[0], filler);
    }
}
