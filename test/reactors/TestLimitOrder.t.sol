// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DeployLimitOrderReactor } from "../../script/Reactor/DeployLimitOrderReactor.s.sol";
import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";
import { LimitOrderReactor } from "../../src/reactors/LimitOrderReactor.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockOracle } from "../mocks/MockOracle.sol";

import { MockUtils } from "../utils/MockUtils.sol";

import { OrderKeyInfo } from "../utils/OrderKeyInfo.t.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

import { CrossChainOrder, Input, Output } from "../../src/interfaces/ISettlementContract.sol";

import { CrossChainLimitOrderType, LimitOrderData } from "../../src/libs/ordertypes/CrossChainLimitOrderType.sol";
import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";

import { Collateral, OrderContext, OrderKey, OrderStatus } from "../../src/interfaces/Structs.sol";
import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import {
    InitiateDeadlineAfterFill,
    InitiateDeadlinePassed,
    InvalidDeadlineOrder,
    OrderAlreadyClaimed
} from "../../src/interfaces/Errors.sol";

import { CrossChainBuilder } from "../utils/CrossChainBuilder.t.sol";
import { OrderDataBuilder } from "../utils/OrderDataBuilder.t.sol";

import { Permit2DomainSeparator, TestBaseReactor } from "./TestBaseReactor.t.sol";
import "forge-std/Test.sol";
import { Test } from "forge-std/Test.sol";

contract TestLimitOrder is TestBaseReactor {
    using SigTransfer for ISignatureTransfer.PermitBatchTransferFrom;

    function testA() external pure { }

    function setUp() public {
        DeployLimitOrderReactor deployer = new DeployLimitOrderReactor();
        (reactor, reactorHelperConfig) = deployer.run();
        (
            tokenToSwapInput,
            tokenToSwapOutput,
            collateralToken,
            localVMOracle,
            remoteVMOracle,
            escrow,
            permit2,
            deployerKey
        ) = reactorHelperConfig.currentConfig();
        DOMAIN_SEPARATOR = Permit2DomainSeparator(permit2).DOMAIN_SEPARATOR();
    }

    /////////////////
    //Valid cases////
    /////////////////

    function test_crossOrder_to_orderKey(
        uint256 inputAmount,
        uint256 outputAmount,
        uint160 fillerCollateralAmount,
        uint160 challengerAmount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        CrossChainOrder memory order = _getCrossOrder(
            inputAmount, outputAmount, SWAPPER, fillerCollateralAmount, challengerAmount, 1, 5, 10, 11, 0
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
            chainId: uint32(block.chainid)
        });
        Output memory actualOutput = orderKey.outputs[0];
        assertEq(keccak256(abi.encode(actualOutput)), keccak256(abi.encode(expectedOutput)));

        //Swapper test
        address actualSWAPPER = orderKey.swapper;
        assertEq(actualSWAPPER, SWAPPER);

        //Oracles tests
        assertEq(orderKey.localOracle, localVMOracle);
        assertEq(orderKey.remoteOracles[0], bytes32(uint256(uint160(remoteVMOracle))));

        //Collateral test
        Collateral memory expectedCollateral = Collateral({
            collateralToken: collateralToken,
            fillerCollateralAmount: fillerCollateralAmount,
            challengerCollateralAmount: challengerAmount
        });
        Collateral memory actualCollateral = orderKey.collateral;
        assertEq(keccak256(abi.encode(actualCollateral)), keccak256(abi.encode(expectedCollateral)));
    }

    function test_multiple_outputs_oracle(
        uint16 inputAmount,
        uint16 outputAmount,
        uint160 fillerCollateralAmount,
        uint32 initiateDeadline,
        uint32 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline,
        uint8 length
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        vm.assume(length > 0);
        _assumeAllDeadlinesCorrectSequence(initiateDeadline, fillDeadline, challengeDeadline, proofDeadline);
        MockERC20(tokenToSwapInput).mint(SWAPPER, uint256(length) * uint256(inputAmount));
        MockERC20(tokenToSwapOutput).mint(fillerAddress, uint256(length) * uint256(outputAmount));

        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitMultipleOrders(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            SWAPPER,
            collateralToken,
            fillerCollateralAmount,
            DEFAULT_CHALLENGER_COLLATERAL_AMOUNT,
            proofDeadline,
            challengeDeadline,
            localVMOracle,
            remoteVMOracle,
            length
        );

        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            address(reactor),
            SWAPPER,
            0,
            uint32(block.chainid),
            uint32(initiateDeadline),
            uint32(fillDeadline)
        );

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.prank(fillerAddress);
        reactor.initiate(order, signature, fillerData);

        MockOracle localVMOracleContract = _getVMOracle(localVMOracle);
        MockOracle remoteVMOracleContract = _getVMOracle(remoteVMOracle);

        uint32[] memory fillTimes = _getFillTimes(length, fillDeadline);

        _fillAndSubmitOracle(remoteVMOracleContract, localVMOracleContract, orderKey, fillTimes);
        reactor.proveOrderFulfillment(orderKey);
    }

    /////////////////
    //Invalid cases//
    /////////////////

    function test_not_enough_balance(
        uint160 inputAmount,
        uint160 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        uint256 amountToTransfer = uint256(inputAmount) + DEFAULT_COLLATERAL_AMOUNT;
        CrossChainOrder memory order = _getCrossOrder(
            amountToTransfer, outputAmount, SWAPPER, fillerCollateralAmount, challengerCollateralAmount, 5, 6, 10, 11, 0
        );

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));
        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(fillerAddress);
        reactor.initiate(order, signature, fillerData);
    }

    function test_not_enough_allowance(
        uint160 inputAmount,
        uint160 outputAmount,
        uint160 fillerCollateralAmount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        vm.assume(fillerCollateralAmount > 0);
        (address BOB, uint256 BOB_KEY) = makeAddrAndKey("bob");
        uint256 amountToTransfer = uint256(inputAmount) + fillerCollateralAmount;
        MockERC20(tokenToSwapInput).mint(BOB, amountToTransfer);
        vm.prank(BOB);
        MockERC20(tokenToSwapInput).approve(permit2, inputAmount);
        CrossChainOrder memory order = _getCrossOrder(
            amountToTransfer,
            outputAmount,
            BOB,
            fillerCollateralAmount,
            DEFAULT_CHALLENGER_COLLATERAL_AMOUNT,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE,
            0
        );

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            BOB_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(fillerAddress);
        reactor.initiate(order, signature, fillerData);
    }

    function _orderType() internal pure override returns (bytes memory) {
        return CrossChainLimitOrderType.getOrderType();
    }

    function _initiateOrder(
        uint256 _nonce,
        address _swapper,
        uint256 _inputAmount,
        uint256 _outputAmount,
        uint256 _fillerCollateralAmount,
        uint256 _challengerCollateralAmount,
        address _fillerSender,
        uint32 initiateDeadline,
        uint32 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline
    ) internal override returns (OrderKey memory) {
        CrossChainOrder memory order = _getCrossOrder(
            _inputAmount,
            _outputAmount,
            _swapper,
            _fillerCollateralAmount,
            _challengerCollateralAmount,
            initiateDeadline,
            fillDeadline,
            challengeDeadline,
            proofDeadline,
            _nonce
        );

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.prank(_fillerSender);
        return reactor.initiate(order, signature, fillerData);
    }

    function _getTypeAndDataHashes(CrossChainOrder calldata order)
        public
        pure
        override
        returns (bytes32 typeHash, bytes32 dataHash, bytes32 orderHash)
    {
        LimitOrderData memory limitOrderData = abi.decode(order.orderData, (LimitOrderData));
        typeHash = CrossChainLimitOrderType.orderTypeHash();
        dataHash = CrossChainLimitOrderType.hashOrderDataM(limitOrderData);
        orderHash = CrossChainOrderType.hash(order, typeHash, dataHash);
    }

    function _getCrossOrder(
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
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
            collateralToken,
            fillerCollateralAmount,
            challengerCollateralAmount,
            proofDeadline,
            challengeDeadline,
            localVMOracle,
            remoteVMOracle
        );
        order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            address(reactor),
            recipient,
            nonce,
            uint32(block.chainid),
            uint32(initiateDeadline),
            uint32(fillDeadline)
        );
    }
}
