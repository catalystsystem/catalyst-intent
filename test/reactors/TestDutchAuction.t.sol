// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DeployDutchOrderReactor } from "../../script/Reactor/DeployDutchOrderReactor.s.sol";
import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";

import { CrossChainOrder, Input } from "../../src/interfaces/ISettlementContract.sol";
import { DutchOrderReactor } from "../../src/reactors/DutchOrderReactor.sol";

import {
    CatalystDutchOrderData, CrossChainDutchOrderType
} from "../../src/libs/ordertypes/CrossChainDutchOrderType.sol";
import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";

import { ExclusiveOrder } from "../../src/validation/ExclusiveOrder.sol";

import { Permit2DomainSeparator, TestBaseReactor } from "./TestBaseReactor.t.sol";

import { Collateral, OrderContext, OrderKey, OrderStatus, OutputDescription } from "../../src/interfaces/Structs.sol";
import { CrossChainBuilder } from "../utils/CrossChainBuilder.t.sol";

import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";
import { OrderDataBuilder } from "../utils/OrderDataBuilder.t.sol";

import { OrderKeyInfo } from "../utils/OrderKeyInfo.t.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockOracle } from "../mocks/MockOracle.sol";
import { MockUtils } from "../utils/MockUtils.sol";

import { FailedValidation } from "../../src/interfaces/Errors.sol";
import { OrderInitiated, OrderProven } from "../../src/interfaces/Events.sol";
import { Input } from "../../src/interfaces/Structs.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

event Transfer(address indexed from, address indexed to, uint256 amount);

event KeysModified(bytes32 key, address initiator, bool config);

contract TestDutchAuction is TestBaseReactor, DeployDutchOrderReactor {
    function testA() external pure { }

    ExclusiveOrder exclusiveOrder;
    address exclusiveOwner;

    function setUp() public {
        address reactorDeployer = vm.addr(deployerKey);
        reactor = deploy(reactorDeployer);
        DOMAIN_SEPARATOR = Permit2DomainSeparator(permit2).DOMAIN_SEPARATOR();
        exclusiveOwner = address(2);
        exclusiveOrder = new ExclusiveOrder(exclusiveOwner);
    }

    /////////////////
    //Valid cases////
    /////////////////

    function test_input_slope(
        uint200 inputAmount,
        uint160 outputAmount,
        uint32 slopeStartingTime,
        uint32 timeIncrement,
        int160 slope
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, uint256(inputAmount) + (slope > 0 ? uint256(timeIncrement) * uint256(int256(slope)) : 0), outputAmount, DEFAULT_COLLATERAL_AMOUNT) {

    )
        public
        approvedAndMinted(
            SWAPPER,
            tokenToSwapInput,
            uint256(inputAmount) + (slope > 0 ? uint256(timeIncrement) * uint256(int256(slope)) : 0),
            outputAmount,
            DEFAULT_COLLATERAL_AMOUNT
        )
    {
        vm.assume(
            timeIncrement > 0 && slopeStartingTime < type(uint32).max - DEFAULT_PROOF_DEADLINE
                && timeIncrement <= type(uint32).max - DEFAULT_PROOF_DEADLINE - slopeStartingTime
        );

        uint256 inputAmountAfterDecrement = _dutchInputResult(inputAmount, slope, uint256(timeIncrement));
        vm.assume(inputAmountAfterDecrement != 0);

        vm.warp(slopeStartingTime);

        uint32 timeAtExecution = slopeStartingTime + timeIncrement;

        uint32 challengeDeadline = timeAtExecution + DEFAULT_CHALLENGE_DEADLINE;
        uint32 proofDeadline = timeAtExecution + DEFAULT_PROOF_DEADLINE;

        (uint256 swapperBalanceBefore, uint256 reactorBalanceBefore) =
            MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, address(reactor));
        CatalystDutchOrderData memory currentDutchOrderData = OrderDataBuilder.getDutchOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            SWAPPER,
            collateralToken,
            DEFAULT_COLLATERAL_AMOUNT,
            DEFAULT_CHALLENGER_COLLATERAL_AMOUNT,
            challengeDeadline,
            proofDeadline,
            localVMOracle,
            remoteVMOracle
        );
        assertEq(reactorBalanceBefore, 0);

        int256[] memory inputSlopes = new int256[](1);
        inputSlopes[0] = slope;

        currentDutchOrderData =
            _withSlopesData(currentDutchOrderData, slopeStartingTime, inputSlopes, currentDutchOrderData.outputSlopes);

        CrossChainOrder memory crossOrder = CrossChainBuilder.getCrossChainOrder(
            currentDutchOrderData,
            address(reactor),
            SWAPPER,
            DEFAULT_ORDER_NONCE,
            uint32(block.chainid),
            timeAtExecution + DEFAULT_INITIATE_DEADLINE,
            timeAtExecution + DEFAULT_FILL_DEADLINE
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(crossOrder, reactor);
        uint256[] memory permittedAmounts;
        if (slope <= 0) {
            permittedAmounts = Permit2Lib.inputsToPermittedAmounts(orderKey.inputs);
        } else {
            uint256 maxTimePass = uint256(crossOrder.initiateDeadline) - uint256(slopeStartingTime);
            permittedAmounts = new uint256[](1);
            permittedAmounts[0] = inputAmount + uint256(int256(slope)) * maxTimePass;
        }

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, permittedAmounts, address(reactor), crossOrder.initiateDeadline);

        bytes32 crossOrderHash = this._getWitnessHash(crossOrder, currentDutchOrderData);

        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch,
            SWAPPER_PRIVATE_KEY,
            _getFullPermitTypeHash(),
            crossOrderHash,
            DOMAIN_SEPARATOR,
            address(reactor)
        );

        vm.warp(timeAtExecution);
        vm.prank(fillerAddress);
        vm.expectCall(
            tokenToSwapInput,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", SWAPPER, address(reactor), inputAmountAfterDecrement
            )
        );
        vm.expectEmit();
        emit Transfer(SWAPPER, address(reactor), inputAmountAfterDecrement);
        reactor.initiate(crossOrder, signature, fillDataV1);

        (uint256 swapperBalanceAfter, uint256 reactorBalanceAfter) =
            MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, address(reactor));

        assertEq(reactorBalanceAfter, inputAmountAfterDecrement);
        assertEq(swapperBalanceAfter, swapperBalanceBefore - inputAmountAfterDecrement);
    }

    function test_output_slope(
        uint256 inputAmount,
        uint160 outputAmount,
        uint32 slopeStartingTime,
        uint32 timeIncrement,
        int160 slope
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, DEFAULT_COLLATERAL_AMOUNT) {
        uint32 PROOF_DEADLINE_INCREMENT = DEFAULT_PROOF_DEADLINE;
        uint256 timePassed = uint256(timeIncrement);
        int256 slopeParsed = int256(slope);

        vm.assume(
            timeIncrement > 0 && slopeStartingTime < type(uint32).max - PROOF_DEADLINE_INCREMENT
                && timeIncrement <= type(uint32).max - PROOF_DEADLINE_INCREMENT - slopeStartingTime
        );
        vm.assume(slope > 0);

        uint256 outputAmountAfterIncrement = _dutchOutputResult(outputAmount, slopeParsed, timePassed);
        if (outputAmountAfterIncrement == 0) return;
        MockERC20(tokenToSwapOutput).mint(fillerAddress, outputAmountAfterIncrement - outputAmount);

        vm.warp(slopeStartingTime);

        uint32 challengeDeadline = slopeStartingTime + timeIncrement + DEFAULT_CHALLENGE_DEADLINE;
        uint32 proofDeadline = slopeStartingTime + timeIncrement + PROOF_DEADLINE_INCREMENT;
        uint32 fillDeadline = slopeStartingTime + timeIncrement + DEFAULT_FILL_DEADLINE;
        MockOracle localVMOracleContract = _getVMOracle(localVMOracle);
        MockOracle remoteVMOracleContract = _getVMOracle(remoteVMOracle);

        CatalystDutchOrderData memory currentDutchOrderData = OrderDataBuilder.getDutchOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            SWAPPER,
            collateralToken,
            DEFAULT_COLLATERAL_AMOUNT,
            DEFAULT_CHALLENGER_COLLATERAL_AMOUNT,
            challengeDeadline,
            proofDeadline,
            localVMOracle,
            remoteVMOracle
        );

        int256[] memory outputSlopes = new int256[](1);
        outputSlopes[0] = slope;
        uint32[] memory fillDeadlines = _getFillDeadlines(1, fillDeadline);

        currentDutchOrderData =
            _withSlopesData(currentDutchOrderData, slopeStartingTime, currentDutchOrderData.inputSlopes, outputSlopes);

        CrossChainOrder memory crossOrder = CrossChainBuilder.getCrossChainOrder(
            currentDutchOrderData,
            address(reactor),
            SWAPPER,
            DEFAULT_ORDER_NONCE,
            uint32(block.chainid),
            slopeStartingTime + timeIncrement + DEFAULT_INITIATE_DEADLINE,
            fillDeadline
        );
        vm.warp(slopeStartingTime + timeIncrement);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(crossOrder, reactor);
        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(
            orderKey,
            Permit2Lib.inputsToPermittedAmounts(orderKey.inputs),
            address(reactor),
            crossOrder.initiateDeadline
        );

        bytes32 crossOrderHash = this._getWitnessHash(crossOrder, currentDutchOrderData);

        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch,
            SWAPPER_PRIVATE_KEY,
            _getFullPermitTypeHash(),
            crossOrderHash,
            DOMAIN_SEPARATOR,
            address(reactor)
        );
        vm.prank(fillerAddress);
        vm.expectEmit();
        emit OrderInitiated(orderHash, fillerAddress, fillDataV1, orderKey);
        reactor.initiate(crossOrder, signature, fillDataV1);

        vm.expectCall(
            tokenToSwapOutput,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", fillerAddress, SWAPPER, outputAmountAfterIncrement
            )
        );

        vm.expectEmit();
        emit Transfer(fillerAddress, SWAPPER, outputAmountAfterIncrement);

        _fillAndSubmitOracle(remoteVMOracleContract, localVMOracleContract, orderKey, fillDeadlines);

        vm.prank(fillerAddress);
        reactor.proveOrderFulfilment(orderKey, hex"");

        (uint256 swapperBalanceAfter, uint256 fillerBalanceAfter) =
            MockUtils.getCurrentBalances(tokenToSwapOutput, SWAPPER, fillerAddress);

        assertEq(swapperBalanceAfter, outputAmountAfterIncrement);
        assertEq(fillerBalanceAfter, 0);
    }

    function test_input_and_output_slopes(
        uint200 inputAmount,
        uint160 outputAmount,
        uint32 slopeStartingTime,
        uint32 timeIncrement,
        int160 inputSlope,
        int160 outputSlope
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, DEFAULT_COLLATERAL_AMOUNT) {
        uint256 timePassed = uint256(timeIncrement);
        int256 inputSlopeParsed = int256(inputSlope);
        int256 outputSlopeParsed = int256(outputSlope);

        vm.assume(
            timeIncrement > 0 && slopeStartingTime < type(uint32).max - DEFAULT_PROOF_DEADLINE
                && timeIncrement <= type(uint32).max - DEFAULT_PROOF_DEADLINE - slopeStartingTime
        );
        vm.assume(outputSlopeParsed > 0 && inputSlopeParsed < 0);

        uint256 inputAmountAfterDecrement = _dutchInputResult(inputAmount, inputSlopeParsed, timePassed);
        vm.assume(inputAmountAfterDecrement != 0);

        uint256 outputAmountAfterIncrement = _dutchOutputResult(outputAmount, outputSlopeParsed, timePassed);
        if (outputAmountAfterIncrement == 0) return;
        MockERC20(tokenToSwapOutput).mint(fillerAddress, outputAmountAfterIncrement - outputAmount);

        vm.warp(slopeStartingTime);

        uint32 fillDeadline = slopeStartingTime + timeIncrement + DEFAULT_FILL_DEADLINE;

        CatalystDutchOrderData memory currentDutchOrderData = OrderDataBuilder.getDutchOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            SWAPPER,
            collateralToken,
            DEFAULT_COLLATERAL_AMOUNT,
            DEFAULT_CHALLENGER_COLLATERAL_AMOUNT,
            slopeStartingTime + timeIncrement + DEFAULT_CHALLENGE_DEADLINE,
            slopeStartingTime + timeIncrement + DEFAULT_PROOF_DEADLINE,
            localVMOracle,
            remoteVMOracle
        );

        int256[] memory inputSlopes = new int256[](1);
        inputSlopes[0] = inputSlopeParsed;

        int256[] memory outputSlopes = new int256[](1);
        outputSlopes[0] = outputSlopeParsed;
        uint32[] memory fillDeadlines = _getFillDeadlines(1, fillDeadline);

        currentDutchOrderData = _withSlopesData(currentDutchOrderData, slopeStartingTime, inputSlopes, outputSlopes);

        CrossChainOrder memory crossOrder = CrossChainBuilder.getCrossChainOrder(
            currentDutchOrderData,
            address(reactor),
            SWAPPER,
            DEFAULT_ORDER_NONCE,
            uint32(block.chainid),
            slopeStartingTime + timeIncrement + DEFAULT_INITIATE_DEADLINE,
            fillDeadline
        );
        vm.warp(slopeStartingTime + timeIncrement);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(crossOrder, reactor);
        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(
            orderKey,
            Permit2Lib.inputsToPermittedAmounts(currentDutchOrderData.inputs),
            address(reactor),
            crossOrder.initiateDeadline
        );

        bytes32 crossOrderHash = this._getWitnessHash(crossOrder, currentDutchOrderData);

        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch,
            SWAPPER_PRIVATE_KEY,
            _getFullPermitTypeHash(),
            crossOrderHash,
            DOMAIN_SEPARATOR,
            address(reactor)
        );
        vm.prank(fillerAddress);
        emit OrderInitiated(orderHash, fillerAddress, fillDataV1, orderKey);
        reactor.initiate(crossOrder, signature, fillDataV1);

        vm.expectCall(
            tokenToSwapOutput,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", fillerAddress, SWAPPER, outputAmountAfterIncrement
            )
        );

        _fillAndSubmitOracle(_getVMOracle(remoteVMOracle), _getVMOracle(localVMOracle), orderKey, fillDeadlines);

        vm.prank(fillerAddress);
        vm.expectEmit();
        emit OrderProven(orderHash, fillerAddress);
        reactor.proveOrderFulfilment(orderKey, hex"");

        uint256 swapperInputBalanceAfter = MockERC20(tokenToSwapInput).balanceOf(SWAPPER);
        uint256 swapperOutputBalanceAfter = MockERC20(tokenToSwapOutput).balanceOf(SWAPPER);
        uint256 fillerInputBalanceAfter = MockERC20(tokenToSwapInput).balanceOf(fillerAddress);
        uint256 fillerOutputBalanceAfter = MockERC20(tokenToSwapOutput).balanceOf(fillerAddress);
        uint256 reactorInputBalanceAfter = MockERC20(tokenToSwapInput).balanceOf(address(reactor));

        assertEq(swapperInputBalanceAfter, inputAmount - inputAmountAfterDecrement);
        assertEq(swapperOutputBalanceAfter, outputAmountAfterIncrement);
        assertEq(fillerInputBalanceAfter, inputAmountAfterDecrement);
        assertEq(fillerOutputBalanceAfter, 0);
        assertEq(reactorInputBalanceAfter, 0);
    }

    function test_allow_list_exclusive_order(bytes32 key, address initiator, bool config) public {
        vm.assume(bytes12(key) != bytes12(0));

        vm.expectEmit();
        emit KeysModified(key, initiator, config);

        vm.prank(exclusiveOwner);
        exclusiveOrder.setAllowList(key, initiator, config);

        assertEq(exclusiveOrder.validate(key, initiator), config);
    }

    /////////////////
    //Invalid cases//
    /////////////////

    function test_input_lengths_no_match(
        uint256 inputAmount,
        uint160 outputAmount,
        int256 slope
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, DEFAULT_COLLATERAL_AMOUNT) {
        CatalystDutchOrderData memory currentDutchOrderData = OrderDataBuilder.getDutchOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            SWAPPER,
            collateralToken,
            DEFAULT_COLLATERAL_AMOUNT,
            DEFAULT_CHALLENGER_COLLATERAL_AMOUNT,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE,
            localVMOracle,
            remoteVMOracle
        );

        int256[] memory inputSlopes = new int256[](2);
        inputSlopes[0] = slope;
        inputSlopes[1] = slope;

        currentDutchOrderData = _withSlopesData(
            currentDutchOrderData, uint32(block.timestamp) + 1, inputSlopes, currentDutchOrderData.outputSlopes
        );

        CrossChainOrder memory crossOrder = CrossChainBuilder.getCrossChainOrder(
            currentDutchOrderData,
            address(reactor),
            SWAPPER,
            DEFAULT_ORDER_NONCE,
            uint32(block.chainid),
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE
        );

        vm.expectRevert(
            abi.encodeWithSignature(
                "LengthsDoesNotMatch(uint256,uint256)", currentDutchOrderData.inputs.length, inputSlopes.length
            )
        );

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(crossOrder, reactor);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(
            orderKey,
            Permit2Lib.inputsToPermittedAmounts(orderKey.inputs),
            address(reactor),
            crossOrder.initiateDeadline
        );

        bytes32 crossOrderHash = this._getWitnessHash(crossOrder, currentDutchOrderData);

        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch,
            SWAPPER_PRIVATE_KEY,
            _getFullPermitTypeHash(),
            crossOrderHash,
            DOMAIN_SEPARATOR,
            address(reactor)
        );
        vm.expectRevert(
            abi.encodeWithSignature(
                "LengthsDoesNotMatch(uint256,uint256)", currentDutchOrderData.inputs.length, inputSlopes.length
            )
        );

        vm.prank(fillerAddress);
        reactor.initiate(crossOrder, signature, fillDataV1);
    }

    function test_output_lengths_no_match(
        uint256 inputAmount,
        uint160 outputAmount,
        int256 slope
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, DEFAULT_COLLATERAL_AMOUNT) {
        CatalystDutchOrderData memory currentDutchOrderData = OrderDataBuilder.getDutchOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            SWAPPER,
            collateralToken,
            DEFAULT_COLLATERAL_AMOUNT,
            DEFAULT_CHALLENGER_COLLATERAL_AMOUNT,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE,
            localVMOracle,
            remoteVMOracle
        );

        int256[] memory outputSlopes = new int256[](2);
        outputSlopes[0] = slope;
        outputSlopes[1] = slope;

        currentDutchOrderData = _withSlopesData(
            currentDutchOrderData, uint32(block.timestamp) + 1, currentDutchOrderData.inputSlopes, outputSlopes
        );

        CrossChainOrder memory crossOrder = CrossChainBuilder.getCrossChainOrder(
            currentDutchOrderData,
            address(reactor),
            SWAPPER,
            DEFAULT_ORDER_NONCE,
            uint32(block.chainid),
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE
        );
        vm.expectRevert(
            abi.encodeWithSignature(
                "LengthsDoesNotMatch(uint256,uint256)", currentDutchOrderData.outputs.length, outputSlopes.length
            )
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(crossOrder, reactor);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(
            orderKey,
            Permit2Lib.inputsToPermittedAmounts(orderKey.inputs),
            address(reactor),
            crossOrder.initiateDeadline
        );

        bytes32 crossOrderHash = this._getWitnessHash(crossOrder, currentDutchOrderData);

        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch,
            SWAPPER_PRIVATE_KEY,
            _getFullPermitTypeHash(),
            crossOrderHash,
            DOMAIN_SEPARATOR,
            address(reactor)
        );

        vm.expectRevert(
            abi.encodeWithSignature(
                "LengthsDoesNotMatch(uint256,uint256)", currentDutchOrderData.outputs.length, outputSlopes.length
            )
        );
        vm.prank(fillerAddress);
        reactor.initiate(crossOrder, signature, fillDataV1);
    }

    function test_failed_validation(
        uint256 inputAmount,
        uint160 outputAmount,
        bytes32 context,
        uint32 slopeStartingTime
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, DEFAULT_COLLATERAL_AMOUNT) {
        vm.assume(slopeStartingTime > block.timestamp);
        vm.assume(context != bytes32(uint256(uint160(exclusiveOwner))));
        CatalystDutchOrderData memory currentDutchOrderData = OrderDataBuilder.getDutchOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            SWAPPER,
            collateralToken,
            DEFAULT_COLLATERAL_AMOUNT,
            DEFAULT_CHALLENGER_COLLATERAL_AMOUNT,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE,
            localVMOracle,
            remoteVMOracle
        );
        currentDutchOrderData = _withVerification(currentDutchOrderData, context, address(exclusiveOrder));
        currentDutchOrderData = _withSlopesData(
            currentDutchOrderData,
            slopeStartingTime,
            currentDutchOrderData.inputSlopes,
            currentDutchOrderData.outputSlopes
        );
        CrossChainOrder memory crossOrder = CrossChainBuilder.getCrossChainOrder(
            currentDutchOrderData,
            address(reactor),
            SWAPPER,
            DEFAULT_ORDER_NONCE,
            uint32(block.chainid),
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(crossOrder, reactor);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(
            orderKey,
            Permit2Lib.inputsToPermittedAmounts(orderKey.inputs),
            address(reactor),
            crossOrder.initiateDeadline
        );

        bytes32 crossOrderHash = this._getWitnessHash(crossOrder, currentDutchOrderData);

        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch,
            SWAPPER_PRIVATE_KEY,
            _getFullPermitTypeHash(),
            crossOrderHash,
            DOMAIN_SEPARATOR,
            address(reactor)
        );
        vm.prank(fillerAddress);
        vm.expectRevert(FailedValidation.selector);
        reactor.initiate(crossOrder, signature, fillDataV1);
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
        uint32 proofDeadline,
        bytes memory fillData
    ) internal virtual override returns (OrderKey memory) {
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

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(
            orderKey, Permit2Lib.inputsToPermittedAmounts(orderKey.inputs), address(reactor), order.initiateDeadline
        );

        bytes memory signature = SigTransfer.crossOrdergetPermitBatchWitnessSignature(
            permitBatch,
            SWAPPER_PRIVATE_KEY,
            _getFullPermitTypeHash(),
            crossOrderHash,
            DOMAIN_SEPARATOR,
            address(reactor)
        );
        vm.prank(_fillerSender);
        return reactor.initiate(order, signature, fillData);
    }

    function test_set_invalid_exclusive_key(address initiator, bool config) public {
        bytes32 key = bytes32(0);

        vm.expectRevert(ExclusiveOrder.KeyCannotHave12EmptyBytes.selector);
        vm.prank(exclusiveOwner);
        exclusiveOrder.setAllowList(key, initiator, config);
    }

    function _withSlopesData(
        CatalystDutchOrderData memory currentCatalystDutchOrderData,
        uint32 slopeStaringTime,
        int256[] memory inputSlopes,
        int256[] memory outputSlopes
    ) internal pure returns (CatalystDutchOrderData memory catalystDutchOrderData) {
        catalystDutchOrderData = currentCatalystDutchOrderData;
        catalystDutchOrderData.slopeStartingTime = slopeStaringTime;
        catalystDutchOrderData.inputSlopes = inputSlopes;
        catalystDutchOrderData.outputSlopes = outputSlopes;
    }

    function _withVerification(
        CatalystDutchOrderData memory currentCatalystDutchOrderData,
        bytes32 verificationContext,
        address verificationContract
    ) internal pure returns (CatalystDutchOrderData memory catalystDutchOrderData) {
        catalystDutchOrderData = currentCatalystDutchOrderData;
        catalystDutchOrderData.verificationContext = verificationContext;
        catalystDutchOrderData.verificationContract = verificationContract;
    }

    function _dutchInputResult(uint256 inputAmount, int256 slope, uint256 timePassed) internal pure returns (uint256) {
        if (slope == 0) return inputAmount;
        if (slope > 0) {
            if (type(uint256).max - inputAmount > timePassed * uint256(slope)) {
                return inputAmount + timePassed * uint256(slope);
            }
        } else {
            if (inputAmount / timePassed > uint256(-slope)) return inputAmount - timePassed * uint256(-slope);
        }
        return 0;
    }

    function _dutchOutputResult(
        uint256 outputAmount,
        int256 slope,
        uint256 timePassed
    ) internal pure returns (uint256) {
        if (type(uint256).max - outputAmount > timePassed * uint256(slope)) {
            return outputAmount + timePassed * uint256(slope);
        }
        return 0;
    }

    function _getFullPermitTypeHash() internal pure override returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                SigTransfer.PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
                CrossChainDutchOrderType.PERMIT2_DUTCH_ORDER_WITNESS_STRING_TYPE
            )
        );
    }

    function _getWitnessHash(
        CrossChainOrder calldata order,
        CatalystDutchOrderData memory dutchOrderData
    ) public pure returns (bytes32) {
        return CrossChainDutchOrderType.crossOrderHash(order, dutchOrderData);
    }

    function _getCrossOrderWithWitnessHash(
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient,
        uint256 fillerAmount,
        uint256 challengerCollateralAmount,
        uint32 initiateDeadline,
        uint32 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline,
        uint256 nonce
    ) internal view virtual override returns (CrossChainOrder memory order, bytes32 witnessHash) {
        CatalystDutchOrderData memory dutchOrderData = OrderDataBuilder.getDutchOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            recipient,
            collateralToken,
            fillerAmount,
            challengerCollateralAmount,
            challengeDeadline,
            proofDeadline,
            localVMOracle,
            remoteVMOracle
        );

        order = CrossChainBuilder.getCrossChainOrder(
            dutchOrderData,
            address(reactor),
            recipient,
            nonce,
            uint32(block.chainid),
            uint32(initiateDeadline),
            uint32(fillDeadline)
        );
        witnessHash = this._getWitnessHash(order, dutchOrderData);
    }
}
