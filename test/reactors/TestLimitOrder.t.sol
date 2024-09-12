// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DeployLimitOrderReactor } from "../../script/Reactor/DeployLimitOrderReactor.s.sol";
import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";
import { LimitOrderReactor } from "../../src/reactors/LimitOrderReactor.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockOracle } from "../mocks/MockOracle.sol";

import { MockUtils } from "../utils/MockUtils.sol";

import { OrderKeyInfo } from "../utils/OrderKeyInfo.t.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

import { CrossChainOrder, Input } from "../../src/interfaces/ISettlementContract.sol";

import {
    CatalystLimitOrderData, CrossChainLimitOrderType
} from "../../src/libs/ordertypes/CrossChainLimitOrderType.sol";
import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";

import { Collateral, OrderContext, OrderKey, OrderStatus, OutputDescription } from "../../src/interfaces/Structs.sol";
import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import {
    InitiateDeadlineAfterFill, InitiateDeadlinePassed, InvalidDeadlineOrder
} from "../../src/interfaces/Errors.sol";

import { CrossChainBuilder } from "../utils/CrossChainBuilder.t.sol";
import { OrderDataBuilder } from "../utils/OrderDataBuilder.t.sol";

import { Permit2DomainSeparator, TestBaseReactor } from "./TestBaseReactor.t.sol";
import "forge-std/Test.sol";
import { Test } from "forge-std/Test.sol";

contract TestLimitOrder is TestBaseReactor, DeployLimitOrderReactor {
    using SigTransfer for ISignatureTransfer.PermitBatchTransferFrom;

    function testA() external pure { }

    function setUp() public {
        address reactorDeployer = vm.addr(deployerKey);
        reactor = deploy(reactorDeployer);
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
        (CrossChainOrder memory order,) = _getCrossOrderWithWitnessHash(
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
        OutputDescription memory expectedOutput = OutputDescription({
            token: bytes32(abi.encode(tokenToSwapOutput)),
            amount: outputAmount,
            recipient: bytes32(abi.encode(SWAPPER)),
            chainId: uint32(block.chainid),
            remoteOracle: orderKey.outputs[0].remoteOracle,
            remoteCall: orderKey.outputs[0].remoteCall
        });
        OutputDescription memory actualOutput = orderKey.outputs[0];
        assertEq(keccak256(abi.encode(actualOutput)), keccak256(abi.encode(expectedOutput)));

        //Swapper test
        address actualSWAPPER = orderKey.swapper;
        assertEq(actualSWAPPER, SWAPPER);

        //Oracles tests
        assertEq(orderKey.localOracle, localVMOracle);
        assertEq(orderKey.outputs[0].remoteOracle, bytes32(uint256(uint160(remoteVMOracle))));

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

        CatalystLimitOrderData memory limitOrderData = OrderDataBuilder.getLimitMultipleOrders(
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
        bytes32 crossOrderHash = this._getWitnessHash(order, limitOrderData);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, Permit2Lib.inputsToPermittedAmounts(orderKey.inputs), address(reactor), order.initiateDeadline);

        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch,
            SWAPPER_PRIVATE_KEY,
            _getFullPermitTypeHash(),
            crossOrderHash,
            DOMAIN_SEPARATOR,
            address(reactor)
        );
        vm.prank(fillerAddress);
        reactor.initiate(order, signature, fillerData);

        MockOracle localVMOracleContract = _getVMOracle(localVMOracle);
        MockOracle remoteVMOracleContract = _getVMOracle(remoteVMOracle);

        uint32[] memory fillDeadlines = _getFillDeadlines(length, fillDeadline);

        _fillAndSubmitOracle(remoteVMOracleContract, localVMOracleContract, orderKey, fillDeadlines);
        reactor.proveOrderFulfilment(orderKey, hex"");
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
        (CrossChainOrder memory order, bytes32 crossOrderHash) = _getCrossOrderWithWitnessHash(
            amountToTransfer, outputAmount, SWAPPER, fillerCollateralAmount, challengerCollateralAmount, 5, 6, 10, 11, 0
        );

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, Permit2Lib.inputsToPermittedAmounts(orderKey.inputs), address(reactor), order.initiateDeadline);
        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch,
            SWAPPER_PRIVATE_KEY,
            _getFullPermitTypeHash(),
            crossOrderHash,
            DOMAIN_SEPARATOR,
            address(reactor)
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
        (CrossChainOrder memory order, bytes32 crossOrderHash) = _getCrossOrderWithWitnessHash(
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

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, Permit2Lib.inputsToPermittedAmounts(orderKey.inputs), address(reactor), order.initiateDeadline);

        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch, BOB_KEY, _getFullPermitTypeHash(), crossOrderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(fillerAddress);
        reactor.initiate(order, signature, fillerData);
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
        (CrossChainOrder memory order, bytes32 crossOrderHash) = _getCrossOrderWithWitnessHash(
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

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, Permit2Lib.inputsToPermittedAmounts(orderKey.inputs), address(reactor), order.initiateDeadline);

        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch,
            SWAPPER_PRIVATE_KEY,
            _getFullPermitTypeHash(),
            crossOrderHash,
            DOMAIN_SEPARATOR,
            address(reactor)
        );
        vm.prank(_fillerSender);
        return reactor.initiate(order, signature, fillerData);
    }

    function _getFullPermitTypeHash() internal pure override returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                SigTransfer.PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
                CrossChainLimitOrderType.PERMIT2_LIMIT_ORDER_WITNESS_STRING_TYPE
            )
        );
    }

    function _getWitnessHash(
        CrossChainOrder calldata order,
        CatalystLimitOrderData memory limitOrderData
    ) public pure returns (bytes32) {
        return CrossChainLimitOrderType.crossOrderHash(order, limitOrderData);
    }

    function _getCrossOrderWithWitnessHash(
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
    ) internal view override returns (CrossChainOrder memory order, bytes32 witnessHash) {
        CatalystLimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            recipient,
            collateralToken,
            fillerCollateralAmount,
            challengerCollateralAmount,
            challengeDeadline,
            proofDeadline,
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

        witnessHash = this._getWitnessHash(order, limitOrderData);
    }
}
