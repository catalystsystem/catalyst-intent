// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DeployLimitOrderReactor } from "../script/Reactor/DeployLimitOrderReactor.s.sol";

import { ReactorHelperConfig } from "../script/Reactor/HelperConfig.s.sol";

import { LimitOrderReactor } from "../src/reactors/LimitOrderReactor.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockUtils } from "./utils/MockUtils.sol";

import { OrderKeyInfo } from "./utils/OrderKeyInfo.t.sol";
import { SigTransfer } from "./utils/SigTransfer.t.sol";

import { CrossChainOrder, Input, Output } from "../src/interfaces/ISettlementContract.sol";

import { CrossChainLimitOrderType, LimitOrderData } from "../src/libs/CrossChainLimitOrderType.sol";
import { CrossChainOrderType } from "../src/libs/CrossChainOrderType.sol";

import { Collateral, OrderContext, OrderKey, OrderStatus } from "../src/interfaces/Structs.sol";
import { Permit2Lib } from "../src/libs/Permit2Lib.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { DeadlinesNotSane, InvalidDeadline, OrderAlreadyClaimed } from "../src/interfaces/Errors.sol";

import { CrossChainBuilder } from "./utils/CrossChainBuilder.t.sol";
import { OrderDataBuilder } from "./utils/OrderDataBuilder.t.sol";

import { BaseReactorTest, Permit2DomainSeparator } from "./Reactors/BaseReactorTest.t.sol";
import "forge-std/Test.sol";
import { Test, console } from "forge-std/Test.sol";

contract TestLimitOrder is BaseReactorTest {
    using SigTransfer for ISignatureTransfer.PermitBatchTransferFrom;
    using CrossChainOrderType for CrossChainOrder;

    function setUp() public {
        DeployLimitOrderReactor deployer = new DeployLimitOrderReactor();
        (reactor, reactorHelperConfig) = deployer.run();
        (tokenToSwapInput, tokenToSwapOutput, permit2, deployerKey) = reactorHelperConfig.currentConfig();
        reactorAddress = address(reactor);
        DOMAIN_SEPARATOR = Permit2DomainSeparator(permit2).DOMAIN_SEPARATOR();
    }

    /////////////////
    //Valid cases////
    /////////////////

    function test_crossOrder_to_orderKey(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerAmount,
        uint256 challengerAmount,
        uint16 deadlineIncrement
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount) {
        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            SWAPPER,
            fillerAmount,
            challengerAmount,
            1,
            0,
            address(0),
            address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            reactorAddress,
            SWAPPER,
            0,
            uint32(block.chainid),
            uint32(block.timestamp + deadlineIncrement),
            uint32(block.timestamp + deadlineIncrement)
        );
        OrderKey memory orderKey = reactor.resolveKey(order, hex"");

        //Input tests
        assertEq(orderKey.inputs.length, 1);
        Input memory expectedInput = Input({ token: tokenToSwapInput, amount: inputAmount });
        Input memory actualInput = orderKey.inputs[0];
        assertEq(keccak256(abi.encode(actualInput)), keccak256(abi.encode(expectedInput)));

        //Output tests
        assertEq(orderKey.outputs.length, 1);
        Output memory expectedOutput = Output({
            token: bytes32(abi.encode(tokenToSwapOutput)),
            amount: outputAmount,
            recipient: bytes32(abi.encode(SWAPPER)),
            chainId: uint32(0)
        });
        Output memory actualOutput = orderKey.outputs[0];
        assertEq(keccak256(abi.encode(actualOutput)), keccak256(abi.encode(expectedOutput)));

        //Swapper test
        address actualSWAPPER = orderKey.swapper;
        assertEq(actualSWAPPER, SWAPPER);

        //Oracles tests
        assertEq(orderKey.localOracle, address(0));
        assertEq(orderKey.remoteOracle, bytes32(0));

        //Collateral test
        Collateral memory expectedCollateral = Collateral({
            collateralToken: tokenToSwapInput,
            fillerCollateralAmount: fillerAmount,
            challengerCollateralAmount: challengerAmount
        });
        Collateral memory actualCollateral = orderKey.collateral;
        assertEq(keccak256(abi.encode(actualCollateral)), keccak256(abi.encode(expectedCollateral)));
    }

    /////////////////
    //Invalid cases//
    /////////////////

    function test_not_enough_balance(uint160 amount) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        uint256 amountToTransfer = uint256(amount) + 1 ether;

        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, amountToTransfer, 0, SWAPPER, 1 ether, 0, 1, 0, address(0), address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            reactorAddress,
            SWAPPER,
            0,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 orderHash = this._getLimitOrderHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);
        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        reactor.initiate(order, signature, abi.encode(FILLER));
    }

    function test_not_enough_allowance(uint160 amount) public {
        (address BOB, uint256 BOB_KEY) = makeAddrAndKey("bob");
        uint256 amountToTransfer = uint256(amount) + 1 ether;
        MockERC20(tokenToSwapInput).mint(BOB, amountToTransfer);
        vm.prank(BOB);
        MockERC20(tokenToSwapInput).approve(permit2, amount);
        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, amountToTransfer, 0, BOB, 1 ether, 0, 1, 0, address(0), address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            reactorAddress,
            BOB,
            0,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 orderHash = this._getLimitOrderHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            BOB_KEY, FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        reactor.initiate(order, signature, abi.encode(FILLER));
    }

    function test_invalid_deadline() public {
        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, 20 ether, 0, SWAPPER, 1 ether, 0, 1, 0, address(0), address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            reactorAddress,
            SWAPPER,
            uint32(block.chainid),
            uint32(block.timestamp),
            uint32(block.timestamp),
            0
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 orderHash = this._getLimitOrderHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        vm.expectRevert(InvalidDeadline.selector);
        reactor.initiate(order, signature, abi.encode(FILLER));
    }

    function test_invalid_challenge_deadline(uint256 amount)
        public
        approvedAndMinted(SWAPPER, tokenToSwapInput, amount)
    {
        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, amount, 0, SWAPPER, 1 ether, 0, 10, 20, address(0), address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            reactorAddress,
            SWAPPER,
            0,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 orderHash = this._getLimitOrderHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        vm.expectRevert(DeadlinesNotSane.selector);
        reactor.initiate(order, signature, abi.encode(FILLER));
    }

    // function test_invalid_nonce(uint160 amount) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
    //     _initiateOrder(0, SWAPPER, amount);
    //     MockERC20(tokenToSwapInput).mint(SWAPPER, amount);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             OrderAlreadyClaimed.selector, OrderContext(OrderStatus.Claimed, address(0), FILLER, 0)
    //         )
    //     );
    //     _initiateOrder(0, SWAPPER, amount);
    // }

    function _orderType() internal pure override returns (bytes memory) {
        return CrossChainLimitOrderType.getOrderType();
    }

    function _initiateOrder(uint256 _nonce, address _swapper, uint256 _amount) internal override {
        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, _amount, 0, _swapper, 1 ether, 0, 1, 0, address(0), address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            reactorAddress,
            SWAPPER,
            _nonce,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 orderHash = this._getLimitOrderHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        reactor.initiate(order, signature, abi.encode(FILLER));
    }

    function _getLimitOrderHash(CrossChainOrder calldata order) public pure returns (bytes32) {
        bytes32 orderDataHash = CrossChainLimitOrderType.hashOrderDataM(abi.decode(order.orderData, (LimitOrderData)));
        bytes32 orderTypeHash = CrossChainLimitOrderType.orderTypeHash();
        return order.hash(orderTypeHash, orderDataHash);
    }
}
