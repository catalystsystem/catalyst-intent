// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DeployLimitOrderReactor } from "../../script/Reactor/DeployLimitOrderReactor.s.sol";
import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";
import { LimitOrderReactor } from "../../src/reactors/LimitOrderReactor.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockUtils } from "../utils/MockUtils.sol";

import { OrderKeyInfo } from "../utils/OrderKeyInfo.t.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

import { CrossChainOrder, Input, Output } from "../../src/interfaces/ISettlementContract.sol";

import { CrossChainLimitOrderType, LimitOrderData } from "../../src/libs/CrossChainLimitOrderType.sol";
import { CrossChainOrderType } from "../../src/libs/CrossChainOrderType.sol";

import { Collateral, OrderContext, OrderKey, OrderStatus } from "../../src/interfaces/Structs.sol";
import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { InvalidDeadlineOrder, InitiateDeadlineAfterFill, InitiateDeadlinePassed, OrderAlreadyClaimed } from "../../src/interfaces/Errors.sol";

import { CrossChainBuilder } from "../utils/CrossChainBuilder.t.sol";
import { OrderDataBuilder } from "../utils/OrderDataBuilder.t.sol";

import { BaseReactorTest, Permit2DomainSeparator } from "./BaseReactorTest.t.sol";
import "forge-std/Test.sol";
import { Test } from "forge-std/Test.sol";

contract TestLimitOrder is BaseReactorTest {
    using SigTransfer for ISignatureTransfer.PermitBatchTransferFrom;
    using CrossChainOrderType for CrossChainOrder;
    using CrossChainLimitOrderType for LimitOrderData;

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
        uint256 challengerAmount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount) {
        CrossChainOrder memory order = _getCrossOrder(
            inputAmount, outputAmount, SWAPPER, fillerAmount, challengerAmount, 1, 5, 10, 11, 0
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
            collateralToken: tokenToSwapOutput,
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
        CrossChainOrder memory order = _getCrossOrder(amountToTransfer, 0, SWAPPER, 1 ether, 0, 5, 6, 10, 11, 0);

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);
        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        reactor.initiate(order, signature, abi.encode(FILLER));
    }

    function test_not_enough_allowance(uint160 amount) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        (address BOB, uint256 BOB_KEY) = makeAddrAndKey("bob");
        uint256 amountToTransfer = uint256(amount) + 1 ether;
        MockERC20(tokenToSwapInput).mint(BOB, amountToTransfer);
        vm.prank(BOB);
        MockERC20(tokenToSwapInput).approve(permit2, amount);
        CrossChainOrder memory order = _getCrossOrder(amountToTransfer, 0, BOB, 1 ether, 0, 5, 6, 10, 11, 0);

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            BOB_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        reactor.initiate(order, signature, abi.encode(FILLER));
    }

    function _orderType() internal pure override returns (bytes memory) {
        return CrossChainLimitOrderType.getOrderType();
    }

    function _initiateOrder(uint256 _nonce, address _swapper, uint256 _amount) internal override {
        CrossChainOrder memory order = _getCrossOrder(_amount, 0, _swapper, 1 ether, 0, 5, 6, 10, 11, _nonce);

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        reactor.initiate(order, signature, abi.encode(FILLER));
    }

    function _getTypeAndDataHashes(CrossChainOrder calldata order)
        public
        pure
        override
        returns (bytes32 typeHash, bytes32 dataHash, bytes32 orderHash)
    {
        LimitOrderData memory limitOrderData = abi.decode(order.orderData, (LimitOrderData));
        typeHash = CrossChainLimitOrderType.orderTypeHash();
        dataHash = limitOrderData.hashOrderDataM();
        orderHash = order.hash(typeHash, dataHash);
    }

    function _getCrossOrder(
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient,
        uint256 fillerAmount,
        uint256 challengerAmount,
        uint32 initiateDeadline,
        uint32 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline,
        uint256 nonce
    ) internal view override returns (CrossChainOrder memory order) {
        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            recipient,
            tokenToSwapOutput,
            fillerAmount,
            challengerAmount,
            proofDeadline,
            challengeDeadline,
            address(0),
            address(0)
        );
        order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            reactorAddress,
            recipient,
            nonce,
            uint32(block.chainid),
            uint32(initiateDeadline),
            uint32(fillDeadline)
        );
    }
}
