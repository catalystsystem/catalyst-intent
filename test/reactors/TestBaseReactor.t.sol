// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";

import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";
import { BaseReactor } from "../../src/reactors/BaseReactor.sol";

import { CrossChainOrder, Input, Output } from "../../src/interfaces/ISettlementContract.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockUtils } from "../utils/MockUtils.sol";
import { OrderDataBuilder } from "../utils/OrderDataBuilder.t.sol";

import { CrossChainLimitOrderType, LimitOrderData } from "../../src/libs/ordertypes/CrossChainLimitOrderType.sol";
import { FillerDataLib } from "../../src/libs/FillerDataLib.sol";
import { Test } from "forge-std/Test.sol";

import { OrderContext, OrderKey, OrderStatus } from "../../src/interfaces/Structs.sol";

import {
    InitiateDeadlineAfterFill,
    InitiateDeadlinePassed,
    InvalidDeadlineOrder,
    OrderAlreadyClaimed
} from "../../src/interfaces/Errors.sol";

import { FraudAccepted, OptimisticPayout, OrderChallenged, OrderPurchased } from "../../src/interfaces/Events.sol";

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
    uint256 DEFAULT_COLLATERAL_AMOUNT_CHALLENGER = 10 ** 19;

    uint32 DEFAULT_INITIATE_DEADLINE = 5;
    uint32 DEFAULT_FILL_DEADLINE = 6;
    uint32 DEFAULT_CHALLENGE_DEADLINE = 10;
    uint32 DEFAULT_PROOF_DEADLINE = 11;

    BaseReactor reactor;
    ReactorHelperConfig reactorHelperConfig;
    address tokenToSwapInput;
    address tokenToSwapOutput;
    address permit2;
    uint256 deployerKey;
    address SWAPPER;
    uint256 SWAPPER_PRIVATE_KEY;
    bytes fillerData;
    address fillerAddress;
    bytes32 DOMAIN_SEPARATOR;

    modifier approvedAndMinted(address _user, address _token, uint256 _amount) {
        vm.prank(_user);
        MockERC20(_token).approve(permit2, type(uint256).max);
        vm.prank(fillerAddress);
        MockERC20(tokenToSwapOutput).approve(address(reactor), type(uint256).max);
        vm.prank(fillerAddress);
        MockERC20(tokenToSwapInput).approve(address(reactor), type(uint256).max);
        MockERC20(_token).mint(_user, _amount);
        MockERC20(tokenToSwapOutput).mint(fillerAddress, 20 ether);
        _;
    }

    //Will be used when we test functionalities after initialization like challenges
    modifier orderInitiaited(uint256 _nonce, address _swapper, uint256 _amount) {
        _initiateOrder(_nonce, _swapper, _amount, fillerAddress);
        _;
    }

    constructor() {
        (SWAPPER, SWAPPER_PRIVATE_KEY) = makeAddrAndKey("swapper");
        fillerAddress = address(1);
        fillerData = FillerDataLib._encode1(fillerAddress, 0, 0);
    }

    bytes32 public FULL_ORDER_PERMIT2_TYPE_HASH = keccak256(
        abi.encodePacked(
            SigTransfer.PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
            CrossChainOrderType.permit2WitnessType(_orderType())
        )
    );

    function test_collect_tokens(uint256 amount) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        (uint256 swapperInputBalance, uint256 reactorInputBalance) =
            MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, address(reactor));
        _initiateOrder(0, SWAPPER, amount, fillerAddress);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(address(reactor)), reactorInputBalance + amount);
    }

    // function test_collect_tokens_from_msg_sender(uint256 amount, address sender) public approvedAndMinted(sender, tokenToSwapInput, amount) {
    //     (uint256 swapperInputBalance, uint256 reactorInputBalance) =
    //         MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, address(reactor));
    //     _initiateOrder(0, SWAPPER, amount, sender);
    //     assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
    //     assertEq(MockERC20(tokenToSwapInput).balanceOf(address(reactor)), reactorInputBalance + amount);
    // }

    function test_balances_multiple_orders(uint160 amount)
        public
        approvedAndMinted(SWAPPER, tokenToSwapInput, amount)
    {
        _initiateOrder(0, SWAPPER, amount, fillerAddress);
        MockERC20(tokenToSwapInput).mint(SWAPPER, amount);
        (uint256 swapperInputBalance, uint256 reactorInputBalance) =
            MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, address(reactor));
        _initiateOrder(1, SWAPPER, amount, fillerAddress);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(address(reactor)), reactorInputBalance + amount);
    }

    function test_revert_passed_initiate_deadline(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerAmount,
        uint256 challengerAmount
    ) public {
        CrossChainOrder memory order =
            _getCrossOrder(inputAmount, outputAmount, SWAPPER, fillerAmount, challengerAmount, 0, 1, 5, 10, 0);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.expectRevert(InitiateDeadlinePassed.selector);
        reactor.initiate(order, signature, fillerData);
    }

    function test_revert_challenge_deadline_after_prove(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerAmount,
        uint256 challengerAmount
    ) public {
        CrossChainOrder memory order =
            _getCrossOrder(inputAmount, outputAmount, SWAPPER, fillerAmount, challengerAmount, 1, 2, 11, 10, 0);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.expectRevert(InvalidDeadlineOrder.selector);
        reactor.initiate(order, signature, fillerData);
    }

    function test_revert_challenge_deadline_before_fill(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerAmount,
        uint256 challengerAmount
    ) public {
        CrossChainOrder memory order =
            _getCrossOrder(inputAmount, outputAmount, SWAPPER, fillerAmount, challengerAmount, 1, 3, 2, 10, 0);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.expectRevert(InvalidDeadlineOrder.selector);
        reactor.initiate(order, signature, fillerData);
    }

    //--- Dispute ---//

    function test_dispute_order(
        uint256 amount,
        address challenger
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        address collateralToken = tokenToSwapOutput;
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            amount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        MockERC20(collateralToken).mint(challenger, DEFAULT_COLLATERAL_AMOUNT_CHALLENGER);
        vm.startPrank(challenger);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);

        vm.expectCall(
            collateralToken,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                challenger,
                address(reactor),
                DEFAULT_COLLATERAL_AMOUNT_CHALLENGER
            )
        );
        vm.expectEmit();
        emit Transfer(challenger, address(reactor), DEFAULT_COLLATERAL_AMOUNT_CHALLENGER);
        vm.expectEmit();
        emit OrderChallenged(orderHash, challenger);
        reactor.dispute(orderKey);

        // Assert the new order status is Challenged.
        OrderContext memory orderContext = reactor.getOrderContext(orderKey);
        assertEq(uint8(orderContext.status), uint8(OrderStatus.Challenged));
    }

    function test_revert_dispute_twice(
        uint256 amount,
        address challenger
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        address collateralToken = tokenToSwapOutput;
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            amount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );

        MockERC20(collateralToken).mint(challenger, DEFAULT_COLLATERAL_AMOUNT_CHALLENGER);
        vm.startPrank(challenger);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);

        reactor.dispute(orderKey);

        vm.expectRevert(abi.encodeWithSignature("WrongOrderStatus(uint8)", OrderStatus.Challenged));
        reactor.dispute(orderKey);
    }

    function test_revert_dispute_no_collateral(
        uint256 amount,
        address challenger
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        vm.assume(fillerAddress != challenger);
        vm.assume(SWAPPER != challenger);
        address collateralToken = tokenToSwapOutput;
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            amount,
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
        uint256 amount,
        uint32 challengeDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        uint32 fillDeadline = DEFAULT_FILL_DEADLINE;
        vm.assume(fillDeadline < challengeDeadline);
        vm.assume(challengeDeadline < type(uint32).max - 1 hours);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            amount,
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
        uint256 amount,
        uint32 challengeDeadline,
        uint32 warp
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        uint32 fillDeadline = DEFAULT_FILL_DEADLINE;
        vm.assume(fillDeadline < challengeDeadline);
        vm.assume(challengeDeadline < type(uint32).max - 1 hours);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            amount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            challengeDeadline,
            challengeDeadline + 1 hours
        );

        vm.warp(warp);
        if (warp <= challengeDeadline) {
            vm.expectRevert(
                abi.encodeWithSignature("OrderNotReadyForOptimisticPayout(uint32)", challengeDeadline - warp + 1)
            );
        }
        reactor.optimisticPayout(orderKey);
    }

    function test_optimistic_payout(
        uint256 amount,
        uint32 challengeDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        uint32 fillDeadline = DEFAULT_FILL_DEADLINE;
        vm.assume(fillDeadline < challengeDeadline);
        vm.assume(challengeDeadline < type(uint32).max - 1 hours);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            amount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            challengeDeadline,
            challengeDeadline + 1 hours
        );

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        vm.warp(challengeDeadline + 1);

        vm.expectEmit();
        emit Transfer(address(reactor), fillerAddress, amount);
        vm.expectEmit();
        emit Transfer(address(reactor), fillerAddress, DEFAULT_COLLATERAL_AMOUNT);
        vm.expectEmit();
        emit OptimisticPayout(orderHash);
        // Check that the input are delivered to the filler.
        vm.expectCall(tokenToSwapInput, abi.encodeWithSignature("transfer(address,uint256)", fillerAddress, amount));
        // Check that the collateral is returned to the filler.
        vm.expectCall(
            tokenToSwapOutput,
            abi.encodeWithSignature("transfer(address,uint256)", fillerAddress, DEFAULT_COLLATERAL_AMOUNT)
        );
        // Check that we emitted the payout status.
        reactor.optimisticPayout(orderKey);
    }

    function test_revert_challenged_optimistic_payout(
        uint256 amount,
        uint32 challengeDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        address collateralToken = tokenToSwapOutput;
        uint32 fillDeadline = DEFAULT_FILL_DEADLINE;
        vm.assume(fillDeadline < challengeDeadline);
        vm.assume(challengeDeadline < type(uint32).max - 1 hours);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            amount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            challengeDeadline,
            challengeDeadline + 1 hours
        );

        MockERC20(collateralToken).mint(address(this), DEFAULT_COLLATERAL_AMOUNT_CHALLENGER);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);

        reactor.dispute(orderKey);

        vm.expectRevert(abi.encodeWithSignature("WrongOrderStatus(uint8)", OrderStatus.Challenged));
        reactor.optimisticPayout(orderKey);
    }

    //--- Resolve Disputed Orders ---//

    function test_complete_dispute_settled(
        uint256 amount,
        address challenger,
        address completeDisputer
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        address inputToken = tokenToSwapInput;
        address collateralToken = tokenToSwapOutput;
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            amount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            DEFAULT_PROOF_DEADLINE
        );

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        MockERC20(collateralToken).mint(challenger, DEFAULT_COLLATERAL_AMOUNT_CHALLENGER);
        vm.startPrank(challenger);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);
        reactor.dispute(orderKey);
        vm.stopPrank();

        // We allow anyone to call the function but this caller shouldn't get anything.
        vm.startPrank(completeDisputer);

        uint256 fillCollateral = DEFAULT_COLLATERAL_AMOUNT;
        uint256 collateralForSwapper = fillCollateral / 2;
        uint256 collateralForChallenger = fillCollateral - collateralForSwapper + DEFAULT_COLLATERAL_AMOUNT_CHALLENGER;

        // Check that the input is delivered back.
        vm.expectCall(inputToken, abi.encodeWithSignature("transfer(address,uint256)", SWAPPER, amount));
        vm.expectCall(
            collateralToken, abi.encodeWithSignature("transfer(address,uint256)", SWAPPER, collateralForSwapper)
        );
        vm.expectCall(
            collateralToken, abi.encodeWithSignature("transfer(address,uint256)", challenger, collateralForChallenger)
        );
        vm.expectEmit();
        emit Transfer(address(reactor), SWAPPER, amount);
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
        uint256 amount,
        address challenger,
        address completeDisputer,
        uint32 proofDeadline,
        uint32 warp
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        address collateralToken = tokenToSwapOutput;
        vm.assume(proofDeadline > DEFAULT_CHALLENGE_DEADLINE);
        vm.assume(warp >= DEFAULT_CHALLENGE_DEADLINE);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            amount,
            fillerAddress,
            DEFAULT_INITIATE_DEADLINE,
            DEFAULT_FILL_DEADLINE,
            DEFAULT_CHALLENGE_DEADLINE,
            proofDeadline
        );

        MockERC20(collateralToken).mint(challenger, DEFAULT_COLLATERAL_AMOUNT_CHALLENGER);
        vm.startPrank(challenger);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);
        reactor.dispute(orderKey);
        vm.stopPrank();

        // We allow anyone to call the function but this caller shouldn't get anything.
        vm.startPrank(completeDisputer);

        vm.warp(warp);
        if (warp <= proofDeadline) {
            vm.expectRevert(abi.encodeWithSignature("ProofPeriodHasNotPassed(uint32)", proofDeadline - warp + 1));
        }

        reactor.completeDispute(orderKey);
    }

    function test_revert_complete_non_disputed_settlement(
        uint256 amount,
        address completeDisputer,
        uint32 proofDeadline
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        vm.assume(proofDeadline > DEFAULT_CHALLENGE_DEADLINE);
        vm.assume(proofDeadline < type(uint32).max - 1);
        OrderKey memory orderKey = _initiateOrder(
            0,
            SWAPPER,
            amount,
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
        uint128 amount,
        uint128 fillerCollateralAmount,
        uint128 outputAmount,
        uint16 discount,
        address buyer,
        uint32 newPurchaseDeadline,
        uint16 newOrderDiscount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        address inputToken = tokenToSwapInput;
        address collateralToken = tokenToSwapOutput;
        CrossChainOrder memory order =
            _getCrossOrder(amount, outputAmount, SWAPPER, fillerCollateralAmount, 0, 1, 2, 3, 10, 0);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderPermitOrderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderPermitOrderHash, DOMAIN_SEPARATOR, address(reactor)
        );

        bytes memory customFillerData = FillerDataLib._encode1(fillerAddress, type(uint32).max, discount);
        MockERC20(collateralToken).mint(fillerAddress, fillerCollateralAmount);
        vm.prank(fillerAddress);
        reactor.initiate(order, signature, customFillerData);

        bytes32 orderHash = reactor.getOrderKeyHash(orderKey);

        MockERC20(inputToken).mint(buyer, amount);
        MockERC20(collateralToken).mint(buyer, fillerCollateralAmount);
        vm.startPrank(buyer);
        MockERC20(inputToken).approve(address(reactor), type(uint256).max);
        MockERC20(collateralToken).approve(address(reactor), type(uint256).max);

        uint256 amountAfterDiscount = amount - uint256(amount) * discount / uint256(type(uint16).max);
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
        reactor.purchaseOrder(orderKey, newPurchaseDeadline, newOrderDiscount);

        // Check storage
        OrderContext memory orderContext = reactor.getOrderContext(orderKey);

        // Check that the fillerAddress was change
        assertEq(orderContext.fillerAddress, buyer);
        assertEq(orderContext.orderPurchaseDeadline, newPurchaseDeadline);
        assertEq(orderContext.orderDiscount, newOrderDiscount);
    }

    function test_revert_purchase_non_existing_order(
        uint128 amount,
        uint128 fillerCollateralAmount,
        uint128 outputAmount,
        address buyer,
        uint32 newPurchaseDeadline,
        uint16 newOrderDiscount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        CrossChainOrder memory order =
            _getCrossOrder(amount, outputAmount, SWAPPER, fillerCollateralAmount, 0, 1, 2, 3, 10, 0);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);

        vm.expectRevert(abi.encodeWithSignature("WrongOrderStatus(uint8)", 0));
        vm.prank(buyer);
        reactor.purchaseOrder(orderKey, newPurchaseDeadline, newOrderDiscount);
    }

    function test_revert_purchase_time_passed(
        uint128 amount,
        uint128 fillerCollateralAmount,
        uint128 outputAmount,
        uint16 discount,
        address buyer,
        uint32 originalPurchaseTime,
        uint32 newPurchaseDeadline,
        uint16 newOrderDiscount
    ) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        address collateralToken = tokenToSwapOutput;
        vm.assume(originalPurchaseTime < type(uint32).max - 1);
        CrossChainOrder memory order =
            _getCrossOrder(amount, outputAmount, SWAPPER, fillerCollateralAmount, 0, 1, 2, 3, 10, 0);
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderPermitOrderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderPermitOrderHash, DOMAIN_SEPARATOR, address(reactor)
        );

        bytes memory customFillerData = FillerDataLib._encode1(fillerAddress, originalPurchaseTime, discount);
        MockERC20(collateralToken).mint(fillerAddress, fillerCollateralAmount);
        vm.prank(fillerAddress);
        reactor.initiate(order, signature, customFillerData);

        vm.startPrank(buyer);
        vm.warp(originalPurchaseTime + 1);
        vm.expectRevert(abi.encodeWithSignature("PurchaseTimePassed()"));
        reactor.purchaseOrder(orderKey, newPurchaseDeadline, newOrderDiscount);
    }

    //--- Helpers ---//

    function _orderType() internal virtual returns (bytes memory);

    function _initiateOrder(
        uint256 _nonce,
        address _swapper,
        uint256 _amount,
        address _fillerSender
    ) internal virtual returns (OrderKey memory) {
        return _initiateOrder(
            _nonce,
            _swapper,
            _amount,
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
        uint256 _amount,
        address _fillerSender,
        uint32 initiateDeadline,
        uint32 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline
    ) internal virtual returns (OrderKey memory);

    function _getTypeAndDataHashes(CrossChainOrder calldata order)
        public
        virtual
        returns (bytes32 typeHash, bytes32 dataHash, bytes32 orderHash);

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
    ) internal view virtual returns (CrossChainOrder memory order);
}
