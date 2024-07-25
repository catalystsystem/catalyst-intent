// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";

import { CrossChainOrderType } from "../../src/libs/CrossChainOrderType.sol";
import { BaseReactor } from "../../src/reactors/BaseReactor.sol";

import { CrossChainOrder, Input, Output } from "../../src/interfaces/ISettlementContract.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockUtils } from "../utils/MockUtils.sol";
import { OrderDataBuilder } from "../utils/OrderDataBuilder.t.sol";

import { CrossChainLimitOrderType, LimitOrderData } from "../../src/libs/CrossChainLimitOrderType.sol";
import { FillerDataLib } from "../../src/libs/FillerDataLib.sol";
import { Test } from "forge-std/Test.sol";

import { OrderKey } from "../../src/interfaces/Structs.sol";

import {
    InitiateDeadlineAfterFill,
    InitiateDeadlinePassed,
    InvalidDeadlineOrder,
    OrderAlreadyClaimed
} from "../../src/interfaces/Errors.sol";

import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";

import { OrderKeyInfo } from "../utils/OrderKeyInfo.t.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

interface Permit2DomainSeparator {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

abstract contract BaseReactorTest is Test {
    using SigTransfer for ISignatureTransfer.PermitBatchTransferFrom;

    BaseReactor reactor;
    ReactorHelperConfig reactorHelperConfig;
    address tokenToSwapInput;
    address tokenToSwapOutput;
    address permit2;
    uint256 deployerKey;
    address reactorAddress;
    address SWAPPER;
    uint256 SWAPPER_PRIVATE_KEY;
    bytes fillerData;
    address fillerAddress;
    bytes32 DOMAIN_SEPARATOR;

    modifier approvedAndMinted(address _user, address _token, uint256 _amount) {
        vm.prank(_user);
        MockERC20(_token).approve(permit2, type(uint256).max);
        vm.prank(fillerAddress);
        MockERC20(tokenToSwapOutput).approve(reactorAddress, type(uint256).max);
        vm.prank(fillerAddress);
        MockERC20(tokenToSwapInput).approve(reactorAddress, type(uint256).max);
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
        fillerData = FillerDataLib._encode1(fillerAddress, 2, 2);
    }

    bytes32 public FULL_ORDER_PERMIT2_TYPE_HASH = keccak256(
        abi.encodePacked(
            SigTransfer.PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
            CrossChainOrderType.permit2WitnessType(_orderType())
        )
    );

    function test_collect_tokens(uint256 amount) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        (uint256 swapperInputBalance, uint256 reactorInputBalance) =
            MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, reactorAddress);
        _initiateOrder(0, SWAPPER, amount, fillerAddress);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(reactorAddress), reactorInputBalance + amount);
    }

    // function test_collect_tokens_from_msg_sender(uint256 amount, address sender) public approvedAndMinted(sender, tokenToSwapInput, amount) {
    //     (uint256 swapperInputBalance, uint256 reactorInputBalance) =
    //         MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, reactorAddress);
    //     _initiateOrder(0, SWAPPER, amount, sender);
    //     assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
    //     assertEq(MockERC20(tokenToSwapInput).balanceOf(reactorAddress), reactorInputBalance + amount);
    // }

    function test_balances_multiple_orders(uint160 amount)
        public
        approvedAndMinted(SWAPPER, tokenToSwapInput, amount)
    {
        _initiateOrder(0, SWAPPER, amount, fillerAddress);
        MockERC20(tokenToSwapInput).mint(SWAPPER, amount);
        (uint256 swapperInputBalance, uint256 reactorInputBalance) =
            MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, reactorAddress);
        _initiateOrder(1, SWAPPER, amount, fillerAddress);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(reactorAddress), reactorInputBalance + amount);
    }

    function test_order_hash(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerAmount,
        uint256 challengerAmount
    ) public {
        CrossChainOrder memory order =
            _getCrossOrder(inputAmount, outputAmount, SWAPPER, fillerAmount, challengerAmount, 1, 0, 0, 1, 0);
        (bytes32 typeHash, bytes32 dataHash,) = this._getTypeAndDataHashes(order);
        bytes32 expected = reactor.orderHash(order);
        bytes32 actual = keccak256(
            bytes.concat(
                typeHash,
                bytes20(order.settlementContract),
                bytes20(order.swapper),
                bytes32(order.nonce),
                bytes4(order.originChainId),
                bytes4(order.initiateDeadline),
                bytes4(order.fillDeadline),
                dataHash
            )
        );

        assertEq(expected, actual);
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

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
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

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        vm.expectRevert(InvalidDeadlineOrder.selector);
        reactor.initiate(order, signature, abi.encode(fillerData));
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

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        vm.expectRevert(InvalidDeadlineOrder.selector);
        reactor.initiate(order, signature, abi.encode(fillerData));
    }

    function _orderType() internal virtual returns (bytes memory);

    function _initiateOrder(
        uint256 _nonce,
        address _swapper,
        uint256 _amount,
        address _fillerSender
    ) internal virtual;

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
