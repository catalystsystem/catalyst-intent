// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";

import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";
import { BaseReactor } from "../../src/reactors/BaseReactor.sol";

import { CrossChainOrder, Input, Output, ResolvedCrossChainOrder } from "../../src/interfaces/ISettlementContract.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockOracle } from "../mocks/MockOracle.sol";
import { MockUtils } from "../utils/MockUtils.sol";
import { OrderDataBuilder } from "../utils/OrderDataBuilder.t.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { FillerDataLib } from "../../src/libs/FillerDataLib.sol";
import { CrossChainLimitOrderType, LimitOrderData } from "../../src/libs/ordertypes/CrossChainLimitOrderType.sol";

import { Test, console } from "forge-std/Test.sol";

import { OrderContext, OrderKey, OrderStatus, OutputDescription } from "../../src/interfaces/Structs.sol";

import {
    CannotProveOrder,
    InitiateDeadlineAfterFill,
    InitiateDeadlinePassed,
    InvalidDeadlineOrder
} from "../../src/interfaces/Errors.sol";

import {
    FraudAccepted,
    GovernanceFeeChanged,
    OptimisticPayout,
    OrderChallenged,
    OrderProven,
    OrderPurchaseDetailsModified,
    OrderPurchased
} from "../../src/interfaces/Events.sol";

import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";

import { OrderKeyInfo } from "../utils/OrderKeyInfo.t.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

interface Permit2DomainSeparator {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

event Transfer(address indexed from, address indexed to, uint256 amount);

abstract contract TestBaseReactor is Test {
    function test() external { }

    using SigTransfer for ISignatureTransfer.PermitBatchTransferFrom;

    uint256 DEFAULT_COLLATERAL_AMOUNT = 10 ** 18;
    uint256 DEFAULT_CHALLENGER_COLLATERAL_AMOUNT = 10 ** 19;

    uint32 DEFAULT_INITIATE_DEADLINE = 5;
    uint32 DEFAULT_FILL_DEADLINE = 6;
    uint32 DEFAULT_CHALLENGE_DEADLINE = 10;
    uint32 DEFAULT_PROOF_DEADLINE = 11;

    uint256 constant MAX_GOVERNANCE_FEE = 10 ** 18 * 0.25;
    BaseReactor reactor;
    ReactorHelperConfig reactorHelperConfig;
    address tokenToSwapInput;
    address tokenToSwapOutput;
    address collateralToken;
    address localVMOracle;
    address remoteVMOracle;
    address escrow;
    address permit2;
    uint256 deployerKey;
    address SWAPPER;
    uint256 SWAPPER_PRIVATE_KEY;
    bytes fillerData;
    address fillerAddress;
    bytes32 DOMAIN_SEPARATOR;

    modifier approvedAndMinted(
        address _user,
        address _token,
        uint256 _inputAmount,
        uint256 _outputAmount,
        uint256 _fillerCollateralAmount
    ) {
        vm.prank(_user);
        MockERC20(_token).approve(permit2, type(uint256).max);

        _approveForFiller(fillerAddress, tokenToSwapInput, type(uint256).max);
        _approveForFiller(fillerAddress, tokenToSwapOutput, type(uint256).max);
        _approveForFiller(fillerAddress, collateralToken, type(uint256).max);

        MockERC20(_token).mint(_user, _inputAmount);
        MockERC20(tokenToSwapOutput).mint(fillerAddress, _outputAmount);
        MockERC20(collateralToken).mint(fillerAddress, _fillerCollateralAmount);

        _;
    }

    //Will be used when we test functionalities after initialization like challenges
    modifier orderInitiaited(
        uint256 _nonce,
        address _swapper,
        uint256 _inputAmount,
        uint256 _outputAmount,
        uint256 _fillerCollateralAmount,
        uint256 _challengerCollateralAmount
    ) {
        _initiateOrder(
            _nonce,
            _swapper,
            _inputAmount,
            _outputAmount,
            _challengerCollateralAmount,
            _fillerCollateralAmount,
            fillerAddress
        );
        _;
    }

    constructor() {
        (SWAPPER, SWAPPER_PRIVATE_KEY) = makeAddrAndKey("swapper");
        fillerAddress = address(1);
        fillerData = FillerDataLib._encode1(fillerAddress, 0, 0);
    }

    function test_collect_tokens(
        uint256 inputAmount,
        uint256 outputAmount,
        uint160 fillerCollateralAmount,
        uint160 challengerCollateralAmount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        (uint256 swapperInputBalance, uint256 reactorInputBalance) =
            MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, address(reactor));
        _initiateOrder(
            0, SWAPPER, inputAmount, outputAmount, fillerCollateralAmount, challengerCollateralAmount, fillerAddress
        );
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - inputAmount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(address(reactor)), reactorInputBalance + inputAmount);
    }

    // function test_collect_tokens_from_msg_sender(uint256 amount, address sender) public approvedAndMinted(sender, tokenToSwapInput, amount) {
    //     (uint256 swapperInputBalance, uint256 reactorInputBalance) =
    //         MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, address(reactor));
    //     _initiateOrder(0, SWAPPER, amount, sender);
    //     assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
    //     assertEq(MockERC20(tokenToSwapInput).balanceOf(address(reactor)), reactorInputBalance + amount);
    // }

    function test_balances_multiple_orders(
        uint160 inputAmount,
        uint256 outputAmount,
        uint160 fillerCollateralAmount,
        uint256 challengerCollateralAmount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        _initiateOrder(
            0, SWAPPER, inputAmount, outputAmount, fillerCollateralAmount, challengerCollateralAmount, fillerAddress
        );
        MockERC20(tokenToSwapInput).mint(SWAPPER, inputAmount);
        (uint256 swapperInputBalance, uint256 reactorInputBalance) =
            MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, address(reactor));
        MockERC20(collateralToken).mint(fillerAddress, fillerCollateralAmount);
        _initiateOrder(
            1, SWAPPER, inputAmount, outputAmount, fillerCollateralAmount, challengerCollateralAmount, fillerAddress
        );
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - inputAmount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(address(reactor)), reactorInputBalance + inputAmount);
    }

    function test_revert_passed_initiate_deadline(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount
    ) public {
        CrossChainOrder memory order = _getCrossOrder(
            inputAmount, outputAmount, SWAPPER, fillerCollateralAmount, challengerCollateralAmount, 0, 1, 5, 10, 0
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 crossOrderHash = this._getWitnessHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, _getFullPermitTypeHash(), crossOrderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.expectRevert(InitiateDeadlinePassed.selector);
        reactor.initiate(order, signature, fillerData);
    }

    function test_revert_challenge_deadline_after_prove(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount
    ) public {
        CrossChainOrder memory order = _getCrossOrder(
            inputAmount, outputAmount, SWAPPER, fillerCollateralAmount, challengerCollateralAmount, 1, 2, 11, 10, 0
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 crossOrderHash = this._getWitnessHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, _getFullPermitTypeHash(), crossOrderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.expectRevert(InvalidDeadlineOrder.selector);
        reactor.initiate(order, signature, fillerData);
    }

    function test_revert_challenge_deadline_before_fill(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount
    ) public {
        CrossChainOrder memory order = _getCrossOrder(
            inputAmount, outputAmount, SWAPPER, fillerCollateralAmount, challengerCollateralAmount, 1, 3, 2, 10, 0
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 crossOrderHash = this._getWitnessHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, _getFullPermitTypeHash(), crossOrderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.expectRevert(InvalidDeadlineOrder.selector);
        reactor.initiate(order, signature, fillerData);
    }

    function test_revert_fill_deadline_before_initiate(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        uint32 fillDeadline,
        uint32 initiateDeadline
    ) public {
        vm.assume(fillDeadline < initiateDeadline);

        CrossChainOrder memory order = _getCrossOrder(
            inputAmount,
            outputAmount,
            SWAPPER,
            fillerCollateralAmount,
            challengerCollateralAmount,
            initiateDeadline,
            fillDeadline,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE,
            0
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 crossOrderHash = this._getWitnessHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, _getFullPermitTypeHash(), crossOrderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.expectRevert(InitiateDeadlineAfterFill.selector);
        reactor.initiate(order, signature, fillerData);
    }

    //--- Dispute ---//

    function test_dispute_order(
        uint256 inputAmount,
        uint256 outputAmount,
        uint160 fillerCollateralAmount,
        uint160 challengerCollateralAmount,
        address challenger
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        MockERC20(collateralToken).mint(challenger, challengerCollateralAmount);
        vm.startPrank(challenger);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);

        vm.expectCall(
            collateralToken,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", challenger, address(reactor), challengerCollateralAmount
            )
        );
        vm.expectEmit();
        emit Transfer(challenger, address(reactor), challengerCollateralAmount);
        vm.expectEmit();
        emit OrderChallenged(orderHash, challenger);
        reactor.dispute(orderKey);

        // Assert the new order status is Challenged.
        OrderContext memory orderContext = reactor.getOrderContext(orderKey);
        assertEq(uint8(orderContext.status), uint8(OrderStatus.Challenged));
    }

    function test_revert_dispute_twice(
        uint256 inputAmount,
        uint256 outputAmount,
        uint160 fillerCollateralAmount,
        uint160 challengerCollateralAmount,
        address challenger
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );

        MockERC20(collateralToken).mint(challenger, challengerCollateralAmount);
        vm.startPrank(challenger);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);

        reactor.dispute(orderKey);

        vm.expectRevert(abi.encodeWithSignature("WrongOrderStatus(uint8)", OrderStatus.Challenged));
        reactor.dispute(orderKey);
    }

    function test_revert_dispute_no_collateral(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        address challenger
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        vm.assume(challenger != address(reactor));
        vm.assume(fillerAddress != challenger);
        vm.assume(SWAPPER != challenger);
        vm.assume(challengerCollateralAmount > 0);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );

        vm.startPrank(challenger);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);

        vm.expectRevert(abi.encodeWithSignature("TransferFromFailed()"));
        reactor.dispute(orderKey);
    }

    function test_revert_challenge_too_late(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        uint32 challengeDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        uint32 fillDeadline = DEFAULT_FILL_DEADLINE;
        vm.assume(fillDeadline < challengeDeadline);
        vm.assume(challengeDeadline < type(uint32).max - 1 hours);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            challengeDeadline,
            challengeDeadline + 1 hours
        );

        vm.warp(challengeDeadline + 1);

        vm.expectRevert(abi.encodeWithSignature("ChallengeDeadlinePassed()"));
        reactor.dispute(orderKey);
    }

    //--- Optimistic Payout ---//

    function test_revert_not_ready_for_optimistic_payout(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        uint32 challengeDeadline,
        uint32 warp
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        uint32 fillDeadline = DEFAULT_FILL_DEADLINE;
        vm.assume(fillDeadline < challengeDeadline);
        vm.assume(challengeDeadline < type(uint32).max - 1 hours);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            challengeDeadline,
            challengeDeadline + 1 hours
        );

        vm.warp(warp);
        if (warp <= challengeDeadline) {
            vm.expectRevert(
                abi.encodeWithSignature("OrderNotReadyForOptimisticPayout(uint32)", challengeDeadline)
            );
        }
        reactor.optimisticPayout(orderKey, hex"");
    }

    function test_optimistic_payout(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        uint32 challengeDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        _assumeValidDeadline(DEFAULT_FILL_DEADLINE, challengeDeadline);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            challengeDeadline,
            challengeDeadline + 1 hours
        );

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        vm.warp(challengeDeadline + 1);

        vm.expectEmit();
        emit Transfer(address(reactor), fillerAddress, inputAmount);
        vm.expectEmit();
        emit Transfer(address(reactor), fillerAddress, fillerCollateralAmount);
        vm.expectEmit();
        emit OptimisticPayout(orderHash);
        // Check that the input are delivered to the filler.
        vm.expectCall(
            tokenToSwapInput, abi.encodeWithSignature("transfer(address,uint256)", fillerAddress, inputAmount)
        );
        // Check that the collateral is returned to the filler.
        vm.expectCall(
            collateralToken, abi.encodeWithSignature("transfer(address,uint256)", fillerAddress, fillerCollateralAmount)
        );
        // Check that we emitted the payout status.
        reactor.optimisticPayout(orderKey, hex"");
    }

    function test_revert_challenged_optimistic_payout(
        uint256 inputAmount,
        uint256 outputAmount,
        uint160 fillerCollateralAmount,
        uint160 challengerCollateralAmount,
        uint32 challengeDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        uint32 fillDeadline = DEFAULT_FILL_DEADLINE;
        vm.assume(fillDeadline < challengeDeadline);
        vm.assume(challengeDeadline < type(uint32).max - 1 hours);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            challengeDeadline,
            challengeDeadline + 1 hours
        );

        MockERC20(collateralToken).mint(address(this), challengerCollateralAmount);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);

        reactor.dispute(orderKey);

        vm.expectRevert(abi.encodeWithSignature("WrongOrderStatus(uint8)", OrderStatus.Challenged));
        reactor.optimisticPayout(orderKey, hex"");
    }

    //--- Resolve Disputed Orders ---//

    function test_complete_dispute_settled(
        uint256 inputAmount,
        uint256 outputAmount,
        uint160 fillerCollateralAmount,
        uint160 challengerCollateralAmount,
        address challenger,
        address completeDisputer
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        address inputToken = tokenToSwapInput;
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        MockERC20(collateralToken).mint(challenger, challengerCollateralAmount);
        vm.startPrank(challenger);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);
        reactor.dispute(orderKey);
        vm.stopPrank();

        // We allow anyone to call the function but this caller shouldn't get anything.
        vm.startPrank(completeDisputer);

        uint256 fillCollateral = fillerCollateralAmount;
        uint256 collateralForSwapper = fillCollateral / 2;
        uint256 collateralForChallenger = fillCollateral - collateralForSwapper + challengerCollateralAmount;

        // Check that the input is delivered back.
        vm.expectCall(inputToken, abi.encodeWithSignature("transfer(address,uint256)", SWAPPER, inputAmount));
        vm.expectCall(
            collateralToken, abi.encodeWithSignature("transfer(address,uint256)", SWAPPER, collateralForSwapper)
        );
        vm.expectCall(
            collateralToken, abi.encodeWithSignature("transfer(address,uint256)", challenger, collateralForChallenger)
        );
        vm.expectEmit();
        emit Transfer(address(reactor), SWAPPER, inputAmount);
        vm.expectEmit();
        emit Transfer(address(reactor), SWAPPER, collateralForSwapper);
        vm.expectEmit();
        emit Transfer(address(reactor), challenger, collateralForChallenger);
        vm.expectEmit();
        emit FraudAccepted(orderHash);

        vm.warp(DEFAULT_PROOF_DEADLINE + 1);
        reactor.completeDispute(orderKey);

        // Assert the new order status is fraud.
        OrderContext memory orderContext = reactor.getOrderContext(orderKey);

        assertEq(uint8(orderContext.status), uint8(OrderStatus.Fraud));
    }

    function test_revert_complete_dispute_too_early_settlement(
        uint256 inputAmount,
        uint256 outputAmount,
        uint160 fillerCollateralAmount,
        uint160 challengerCollateralAmount,
        address challenger,
        address completeDisputer,
        uint32 proofDeadline,
        uint32 warp
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        vm.assume(proofDeadline > DEFAULT_CHALLENGE_DEADLINE);
        vm.assume(warp >= DEFAULT_CHALLENGE_DEADLINE);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            proofDeadline
        );

        MockERC20(collateralToken).mint(challenger, challengerCollateralAmount);
        vm.startPrank(challenger);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);
        reactor.dispute(orderKey);
        vm.stopPrank();

        // We allow anyone to call the function but this caller shouldn't get anything.
        vm.startPrank(completeDisputer);

        vm.warp(warp);
        if (warp <= proofDeadline) {
            vm.expectRevert(abi.encodeWithSignature("ProofPeriodHasNotPassed(uint32)", proofDeadline));
        }

        reactor.completeDispute(orderKey);
    }

    function test_revert_complete_non_disputed_settlement(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        address completeDisputer,
        uint32 proofDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        vm.assume(proofDeadline > DEFAULT_CHALLENGE_DEADLINE);
        vm.assume(proofDeadline < type(uint32).max - 1);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            DEFAULT_CHALLENGER_COLLATERAL_AMOUNT,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            proofDeadline
        );

        vm.startPrank(completeDisputer);
        vm.warp(proofDeadline + 1);

        vm.expectRevert(abi.encodeWithSignature("WrongOrderStatus(uint8)", 1));
        reactor.completeDispute(orderKey);
    }

    //--- Buyable Orders ---//

    function test_purchase_order(
        uint128 inputAmount,
        uint128 fillerCollateralAmount,
        uint128 outputAmount,
        uint16 discount,
        address buyer,
        uint32 newPurchaseDeadline,
        uint16 newOrderPurchaseDiscount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        address inputToken = tokenToSwapInput;
        CrossChainOrder memory order =
            _getCrossOrder(inputAmount, outputAmount, SWAPPER, fillerCollateralAmount, 0, 1, 2, 3, 10, 0);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 crossOrderHash = this._getWitnessHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, _getFullPermitTypeHash(), crossOrderHash, DOMAIN_SEPARATOR, address(reactor)
        );

        bytes memory customFillerData = FillerDataLib._encode1(fillerAddress, type(uint32).max, discount);
        MockERC20(collateralToken).mint(fillerAddress, fillerCollateralAmount);
        vm.prank(fillerAddress);
        reactor.initiate(order, signature, customFillerData);

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        MockERC20(inputToken).mint(buyer, inputAmount);
        MockERC20(collateralToken).mint(buyer, fillerCollateralAmount);
        vm.startPrank(buyer);
        MockERC20(inputToken).approve(address(reactor), type(uint256).max);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);

        bytes memory newFillerData = FillerDataLib._encode1(buyer, newPurchaseDeadline, newOrderPurchaseDiscount);

        uint256 amountAfterDiscount = inputAmount - uint256(inputAmount) * discount / uint256(type(uint16).max);
        vm.expectCall(
            collateralToken,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", buyer, fillerAddress, fillerCollateralAmount
            )
        );
        vm.expectCall(
            inputToken,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", buyer, fillerAddress, amountAfterDiscount)
        );
        vm.expectEmit();
        emit Transfer(buyer, fillerAddress, fillerCollateralAmount);
        vm.expectEmit();
        emit Transfer(buyer, fillerAddress, amountAfterDiscount);
        vm.expectEmit();
        emit OrderPurchased(orderHash, buyer);
        reactor.purchaseOrder(orderKey, newFillerData, 0);

        // Check storage
        OrderContext memory orderContext = reactor.getOrderContext(orderKey);

        // Check that the fillerAddress was change
        assertEq(orderContext.fillerAddress, buyer);
        assertEq(orderContext.orderPurchaseDeadline, newPurchaseDeadline);
        assertEq(orderContext.orderPurchaseDiscount, newOrderPurchaseDiscount);
    }

    function test_revert_purchase_non_existing_order(
        uint128 inputAmount,
        uint128 outputAmount,
        uint128 fillerCollateralAmount,
        address buyer,
        uint32 newPurchaseDeadline,
        uint16 newOrderPurchaseDiscount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        CrossChainOrder memory order =
            _getCrossOrder(inputAmount, outputAmount, SWAPPER, fillerCollateralAmount, 0, 1, 2, 3, 10, 0);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);

        bytes memory newFillerData = FillerDataLib._encode1(buyer, newPurchaseDeadline, newOrderPurchaseDiscount);

        vm.expectRevert(abi.encodeWithSignature("WrongOrderStatus(uint8)", 0));
        vm.prank(buyer);
        reactor.purchaseOrder(orderKey, newFillerData, 0);
    }

    function test_revert_purchase_time_passed(
        uint128 inputAmount,
        uint128 outputAmount,
        uint128 fillerCollateralAmount,
        uint16 discount,
        address buyer,
        uint32 originalPurchaseTime,
        uint32 newPurchaseDeadline,
        uint16 newOrderPurchaseDiscount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        vm.assume(originalPurchaseTime < type(uint32).max - 1);
        CrossChainOrder memory order =
            _getCrossOrder(inputAmount, outputAmount, SWAPPER, fillerCollateralAmount, 0, 1, 2, 3, 10, 0);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 crossOrderHash = this._getWitnessHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, _getFullPermitTypeHash(), crossOrderHash, DOMAIN_SEPARATOR, address(reactor)
        );

        bytes memory customFillerData = FillerDataLib._encode1(fillerAddress, originalPurchaseTime, discount);
        MockERC20(collateralToken).mint(fillerAddress, fillerCollateralAmount);
        vm.prank(fillerAddress);
        reactor.initiate(order, signature, customFillerData);

        bytes memory newFillerData = FillerDataLib._encode1(buyer, newPurchaseDeadline, newOrderPurchaseDiscount);

        vm.startPrank(buyer);
        vm.warp(originalPurchaseTime + 1);
        vm.expectRevert(abi.encodeWithSignature("PurchaseTimePassed()"));
        reactor.purchaseOrder(orderKey, newFillerData, 0);
    }

    function test_revert_optimiscallyFilled_purchase_order(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        address purchaser,
        uint32 challengeDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        _assumeValidDeadline(DEFAULT_FILL_DEADLINE, challengeDeadline);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            challengeDeadline,
            challengeDeadline + 1 hours
        );
        vm.warp(challengeDeadline + 1);
        reactor.optimisticPayout(orderKey, hex"");

        vm.expectRevert(abi.encodeWithSignature("WrongOrderStatus(uint8)", uint8(OrderStatus.OptimiscallyFilled)));
        vm.prank(purchaser);
        reactor.purchaseOrder(orderKey, hex"", 0);
    }

    //--- Modify Orders ---//

    function test_modify_order(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        uint32 newPurchaseDeadline,
        uint16 newOrderPurchaseDiscount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        bytes memory newFillerData = FillerDataLib._encode1(fillerAddress, newPurchaseDeadline, newOrderPurchaseDiscount);

        vm.expectEmit();
        emit OrderPurchaseDetailsModified(orderHash, fillerAddress, newPurchaseDeadline, newOrderPurchaseDiscount, bytes32(0));
        vm.prank(fillerAddress);

        reactor.modifyOrderFillerdata(orderKey, newFillerData);
    }

    function test_revert_nonFiller_modify(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        address malleciousModifier,
        uint32 newPurchaseDeadline,
        uint16 newOrderPurchaseDiscount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        vm.assume(malleciousModifier != fillerAddress);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );

        bytes memory newFillerData = FillerDataLib._encode1(fillerAddress, newPurchaseDeadline, newOrderPurchaseDiscount);

        vm.expectRevert(abi.encodeWithSignature("OnlyFiller()"));
        vm.prank(malleciousModifier);
        reactor.modifyOrderFillerdata(orderKey, newFillerData);
    }

    //--- Resolve Orders ---//
    function test_resolve_order(
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient,
        uint256 fillerAmount,
        uint256 challengerAmount,
        uint32 initiateDeadline,
        uint32 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline,
        uint256 nonce,
        uint256 governanceFee
    ) public {
        vm.assume(governanceFee > 0 && governanceFee < MAX_GOVERNANCE_FEE);
        CrossChainOrder memory order = _getCrossOrder(
            inputAmount,
            outputAmount,
            recipient,
            fillerAmount,
            challengerAmount,
            initiateDeadline,
            fillDeadline,
            challengeDeadline,
            proofDeadline,
            nonce
        );

        vm.expectEmit();
        emit GovernanceFeeChanged(0, governanceFee);
        vm.prank(reactor.owner());
        reactor.setGovernanceFee(governanceFee);
        ResolvedCrossChainOrder memory actual = reactor.resolve(order, fillerData);

        Input[] memory inputs = OrderDataBuilder.getInputs(tokenToSwapInput, inputAmount, 1);
        Output[] memory outputs = OrderDataBuilder.getSettlementOutputs(
            bytes32(uint256(uint160(tokenToSwapOutput))),
            outputAmount,
            bytes32(uint256(uint160(recipient))),
            uint32(block.chainid),
            1
        );
        Output[] memory fillerOutputs = new Output[](1);

        if (inputAmount < type(uint256).max / governanceFee) {
            inputAmount = inputAmount - inputAmount * governanceFee / 10 ** 18;
        }

        fillerOutputs[0] = Output({
            token: bytes32(uint256(uint160(inputs[0].token))),
            amount: inputAmount,
            recipient: bytes32(uint256(uint160(fillerAddress))),
            chainId: uint32(block.chainid)
        });

        ResolvedCrossChainOrder memory expected = ResolvedCrossChainOrder({
            settlementContract: address(reactor),
            swapper: recipient,
            nonce: nonce,
            originChainId: uint32(block.chainid),
            initiateDeadline: initiateDeadline,
            fillDeadline: fillDeadline,
            swapperInputs: inputs,
            swapperOutputs: outputs,
            fillerOutputs: fillerOutputs
        });

        assertEq(keccak256(abi.encode(actual)), keccak256(abi.encode(expected)));
    }

    //--- Oracle ---//
    function test_oracle(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        uint32 initiateDeadline,
        uint32 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        _assumeAllDeadlinesCorrectSequence(initiateDeadline, fillDeadline, challengeDeadline, proofDeadline);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            initiateDeadline,
            fillDeadline,
            challengeDeadline,
            proofDeadline
        );

        MockOracle localVMOracleContract = _getVMOracle(localVMOracle);
        MockOracle remoteVMOracleContract = _getVMOracle(remoteVMOracle);

        uint32[] memory fillDeadlines = _getFillDeadlines(1, fillDeadline);

        vm.expectEmit();
        emit Transfer(fillerAddress, SWAPPER, outputAmount);

        vm.expectCall(
            tokenToSwapOutput,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", fillerAddress, SWAPPER, outputAmount)
        );
        _fillAndSubmitOracle(remoteVMOracleContract, localVMOracleContract, orderKey, fillDeadlines);

        vm.expectCall(
            collateralToken, abi.encodeWithSignature("transfer(address,uint256)", fillerAddress, fillerCollateralAmount)
        );

        vm.expectCall(
            tokenToSwapInput, abi.encodeWithSignature("transfer(address,uint256)", fillerAddress, inputAmount)
        );

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        vm.expectEmit();
        emit OrderProven(orderHash, fillerAddress);

        vm.prank(fillerAddress);
        reactor.proveOrderFulfilment(orderKey, hex"");

        OrderContext memory orderContext = reactor.getOrderContext(orderKey);
        assert(orderContext.status == OrderStatus.Proven);
    }

    function test_revert_oracle_cannot_be_proven(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        OrderKey memory orderKey = _initiateOrder(
            0, SWAPPER, inputAmount, outputAmount, fillerCollateralAmount, challengerCollateralAmount, fillerAddress
        );
        vm.expectRevert(CannotProveOrder.selector);
        reactor.proveOrderFulfilment(orderKey, hex"");
    }

    function test_revert_oracle_proven_order(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        uint32 initiateDeadline,
        uint32 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        _assumeAllDeadlinesCorrectSequence(initiateDeadline, fillDeadline, challengeDeadline, proofDeadline);

        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            initiateDeadline,
            fillDeadline,
            challengeDeadline,
            proofDeadline
        );

        MockOracle localVMOracleContract = _getVMOracle(localVMOracle);
        MockOracle remoteVMOracleContract = _getVMOracle(remoteVMOracle);

        uint32[] memory fillDeadlines = _getFillDeadlines(1, fillDeadline);

        vm.expectEmit();
        emit Transfer(fillerAddress, SWAPPER, outputAmount);

        vm.expectCall(
            tokenToSwapOutput,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", fillerAddress, SWAPPER, outputAmount)
        );
        _fillAndSubmitOracle(remoteVMOracleContract, localVMOracleContract, orderKey, fillDeadlines);

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);
        vm.warp(challengeDeadline + 1);
        vm.expectEmit();
        emit OptimisticPayout(orderHash);
        reactor.optimisticPayout(orderKey, hex"");

        vm.expectRevert(abi.encodeWithSignature("WrongOrderStatus(uint8)", uint8(OrderStatus.OptimiscallyFilled)));
        reactor.proveOrderFulfilment(orderKey, hex"");
    }

    function test_oracle_challenged_order(
        uint256 inputAmount,
        uint256 outputAmount,
        uint160 fillerCollateralAmount,
        uint160 challengerCollateralAmount,
        address challenger
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, inputAmount, outputAmount, fillerCollateralAmount) {
        uint256 fillerBalanceBefore = MockERC20(collateralToken).balanceOf(fillerAddress);

        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            inputAmount,
            outputAmount,
            fillerCollateralAmount,
            challengerCollateralAmount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );

        MockERC20(collateralToken).mint(challenger, challengerCollateralAmount);
        vm.startPrank(challenger);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);
        vm.expectCall(
            collateralToken,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", challenger, address(reactor), challengerCollateralAmount
            )
        );
        vm.expectEmit();
        emit Transfer(challenger, address(reactor), challengerCollateralAmount);

        reactor.dispute(orderKey);
        vm.stopPrank();

        MockOracle localVMOracleContract = _getVMOracle(localVMOracle);
        MockOracle remoteVMOracleContract = _getVMOracle(remoteVMOracle);

        uint32[] memory fillDeadlines = _getFillDeadlines(1, DEFAULT_FILL_DEADLINE);

        vm.expectEmit();
        emit Transfer(fillerAddress, SWAPPER, outputAmount);

        vm.expectCall(
            tokenToSwapOutput,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", fillerAddress, SWAPPER, outputAmount)
        );

        _fillAndSubmitOracle(remoteVMOracleContract, localVMOracleContract, orderKey, fillDeadlines);

        vm.expectCall(
            collateralToken,
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                fillerAddress,
                uint256(fillerCollateralAmount) + uint256(challengerCollateralAmount)
            )
        );

        vm.expectCall(
            tokenToSwapInput, abi.encodeWithSignature("transfer(address,uint256)", fillerAddress, inputAmount)
        );

        vm.expectEmit();
        emit OrderProven(reactor.getOrderKeyHash(orderKey), fillerAddress);

        vm.prank(fillerAddress);
        reactor.proveOrderFulfilment(orderKey, hex"");

        OrderContext memory orderContext = reactor.getOrderContext(orderKey);

        assert(orderContext.status == OrderStatus.Proven);
        assertEq(MockERC20(collateralToken).balanceOf(fillerAddress), fillerBalanceBefore + challengerCollateralAmount);
    }

    //--- Helpers ---//

    function _approveForFiller(address _fillerAddress, address _token, uint256 _amount) internal {
        vm.startPrank(_fillerAddress);
        MockERC20(_token).approve(address(reactor), _amount);
        MockERC20(_token).approve(remoteVMOracle, _amount);
        vm.stopPrank();
    }

    function _assumeValidDeadline(uint32 fillDeadline, uint32 challengeDeadline) internal pure {
        vm.assume(fillDeadline < challengeDeadline);
        vm.assume(challengeDeadline < type(uint32).max - 1 hours);
    }

    function _assumeAllDeadlinesCorrectSequence(
        uint32 initiateDeadline,
        uint64 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline
    ) internal view {
        vm.assume(
            block.timestamp < initiateDeadline && initiateDeadline < fillDeadline
                && fillDeadline + block.timestamp < 7 days && fillDeadline < challengeDeadline
                && challengeDeadline < proofDeadline
        );
    }

    function _getVMOracle(address oracleAddress) internal returns (MockOracle oracleContract) {
        oracleContract = MockOracle(oracleAddress);
        oracleContract.setRemoteImplementation(bytes32(block.chainid), abi.encode(escrow));
    }

    function _getFillDeadlines(uint256 length, uint32 fillDeadline) internal pure returns (uint32[] memory fillDeadlines) {
        fillDeadlines = new uint32[](length);
        for (uint256 i; i < length; ++i) {
            fillDeadlines[i] = fillDeadline;
        }
    }

    function _fillAndSubmitOracle(
        MockOracle remoteVMOracleContract,
        MockOracle localVMOracleContract,
        OrderKey memory orderKey,
        uint32[] memory fillDeadlines
    ) internal {
        OutputDescription[] memory outputs = orderKey.outputs;

        bytes memory encodedDestinationAddress = remoteVMOracleContract.encodeDestinationAddress(orderKey.localOracle);
        bytes32 destinationIdentifier = bytes32(block.chainid);

        IMessageEscrowStructs.IncentiveDescription memory incentiveDescription = remoteVMOracleContract.getIncentive();
        vm.deal(fillerAddress, 10 ** 18);

        vm.startPrank(fillerAddress);
        remoteVMOracleContract.fillAndSubmit{ value: remoteVMOracleContract.getTotalIncentive(incentiveDescription) }(
            outputs, fillDeadlines, destinationIdentifier, encodedDestinationAddress, incentiveDescription
        );
        vm.stopPrank();

        bytes memory encodedPayload = localVMOracleContract.encode(outputs, fillDeadlines);

        vm.prank(escrow);

        localVMOracleContract.receiveMessage(
            destinationIdentifier, bytes32(0), abi.encodePacked(orderKey.outputs[0].remoteOracle), encodedPayload
        );
    }

    function _getFullPermitTypeHash() internal virtual returns (bytes32);

    function _getWitnessHash(CrossChainOrder calldata order) public virtual returns (bytes32);

    function _initiateOrder(
        uint256 _nonce,
        address _swapper,
        uint256 _inputAmount,
        uint256 _outputAmount,
        uint256 _fillerCollateralAmount,
        uint256 _challengerCollateralAmount,
        address _fillerSender
    ) internal virtual returns (OrderKey memory) {
        return _initiateOrder(
            _nonce,
            _swapper,
            _inputAmount,
            _outputAmount,
            _fillerCollateralAmount,
            _challengerCollateralAmount,
            _fillerSender,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );
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
    ) internal virtual returns (OrderKey memory);

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
    ) internal view virtual returns (CrossChainOrder memory order);
}
