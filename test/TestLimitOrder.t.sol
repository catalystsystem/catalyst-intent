// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DeployLimitOrderReactor } from "../script/Reactor/DeployLimitOrderReactor.s.sol";

import { ReactorHelperConfig } from "../script/Reactor/HelperConfig.s.sol";

import { LimitOrderReactor } from "../src/reactors/LimitOrderReactor.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";

import { OrderKeyInfo } from "./utils/OrderKeyInfo.t.sol";
import { SigTransfer } from "./utils/SigTransfer.t.sol";

import { CrossChainOrder, Input, Output } from "../src/interfaces/ISettlementContract.sol";

import { CrossChainLimitOrderType, LimitOrderData } from "../src/libs/CrossChainLimitOrderType.sol";

import { Collateral, OrderContext, OrderKey, OrderStatus } from "../src/interfaces/Structs.sol";
import { Permit2Lib } from "../src/libs/Permit2Lib.sol";
import { LimitOrderReactor } from "../src/reactors/LimitOrderReactor.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { InvalidDeadline, OrderAlreadyClaimed } from "../src/interfaces/Errors.sol";

import { CrossChainBuilder } from "./utils/CrossChainBuilder.t.sol";
import { OrderDataBuilder } from "./utils/OrderDataBuilder.t.sol";

import "forge-std/Test.sol";
import { Test, console } from "forge-std/Test.sol";

interface Permit2DomainSeparator {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract TestLimitOrder is Test {
    LimitOrderReactor limitOrderReactor;
    ReactorHelperConfig reactorHelperConfig;
    address tokenToSwapInput;
    address tokenToSwapOutput;
    address permit2;
    uint256 deployerKey;
    address limitOrderReactorAddress;
    address SWAPPER;
    uint256 SWAPPER_PRIVATE_KEY;
    address FILLER = address(1);
    bytes32 DOMAIN_SEPARATOR;

    using SigTransfer for ISignatureTransfer.PermitBatchTransferFrom;

    bytes32 public constant FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH = keccak256(
        abi.encodePacked(
            SigTransfer._PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
            CrossChainLimitOrderType.PERMIT2_WITNESS_TYPE // TODO: generalise
        )
    );

    function setUp() public {
        DeployLimitOrderReactor deployer = new DeployLimitOrderReactor();
        (limitOrderReactor, reactorHelperConfig) = deployer.run();
        (tokenToSwapInput, tokenToSwapOutput, permit2, deployerKey) = reactorHelperConfig.currentConfig();
        limitOrderReactorAddress = address(limitOrderReactor);

        (SWAPPER, SWAPPER_PRIVATE_KEY) = makeAddrAndKey("swapper");
        DOMAIN_SEPARATOR = Permit2DomainSeparator(permit2).DOMAIN_SEPARATOR();
    }

    //Will be used when we test functionalities after initialization like challenges
    modifier orderInitiaited(uint256 _nonce, address _swapper, uint256 _amount) {
        _initiateOrder(_nonce, _swapper, _amount);
        _;
    }

    modifier approvedAndMinted(address _user, address _token, uint256 _amount) {
        vm.prank(_user);
        MockERC20(_token).approve(permit2, type(uint256).max);
        MockERC20(_token).mint(_user, _amount);
        _;
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
            address(0),
            address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            limitOrderReactorAddress,
            SWAPPER,
            0,
            uint32(block.chainid),
            uint32(block.timestamp + deadlineIncrement),
            uint32(block.timestamp + deadlineIncrement)
        );
        OrderKey memory orderKey = limitOrderReactor.resolveKey(order, hex"");

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

    function test_collect_tokens(uint256 amount) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        (uint256 swapperInputBalance,, uint256 reactorInputBalance,) = _getCurrentBalances();
        _initiateOrder(0, SWAPPER, amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(limitOrderReactorAddress), reactorInputBalance + amount);
    }

    function test_balances_multiple_orders(uint160 amount)
        public
        approvedAndMinted(SWAPPER, tokenToSwapInput, amount)
    {
        _initiateOrder(0, SWAPPER, amount);
        MockERC20(tokenToSwapInput).mint(SWAPPER, amount);
        (uint256 swapperInputBalance,, uint256 reactorInputBalance,) = _getCurrentBalances();
        _initiateOrder(1, SWAPPER, amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(limitOrderReactorAddress), reactorInputBalance + amount);
    }

    /////////////////
    //Invalid cases//
    /////////////////

    function test_not_enough_balance(uint160 amount) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        uint256 amountToTransfer = uint256(amount) + 1 ether;

        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, amountToTransfer, 0, SWAPPER, 1 ether, 0, address(0), address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            limitOrderReactorAddress,
            SWAPPER,
            0,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, limitOrderReactor);
        bytes32 orderHash = this._getLimitOrderHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, limitOrderReactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY,
            FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH,
            orderHash,
            DOMAIN_SEPARATOR,
            limitOrderReactorAddress
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        limitOrderReactor.initiate(order, signature, abi.encode(FILLER));
    }

    function test_not_enough_allowance(uint160 amount) public {
        (address BOB, uint256 BOB_KEY) = makeAddrAndKey("bob");
        uint256 amountToTransfer = uint256(amount) + 1 ether;
        MockERC20(tokenToSwapInput).mint(BOB, amountToTransfer);
        vm.prank(BOB);
        MockERC20(tokenToSwapInput).approve(permit2, amount);
        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, amountToTransfer, 0, BOB, 1 ether, 0, address(0), address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            limitOrderReactorAddress,
            BOB,
            0,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, limitOrderReactor);
        bytes32 orderHash = this._getLimitOrderHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, limitOrderReactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            BOB_KEY, FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, limitOrderReactorAddress
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        limitOrderReactor.initiate(order, signature, abi.encode(FILLER));
    }

    function test_invalid_deadline() public {
        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, 20 ether, 0, SWAPPER, 1 ether, 0, address(0), address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            limitOrderReactorAddress,
            SWAPPER,
            uint32(block.chainid),
            uint32(block.timestamp),
            uint32(block.timestamp),
            0
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, limitOrderReactor);
        bytes32 orderHash = this._getLimitOrderHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, limitOrderReactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY,
            FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH,
            orderHash,
            DOMAIN_SEPARATOR,
            limitOrderReactorAddress
        );
        vm.expectRevert(InvalidDeadline.selector);
        limitOrderReactor.initiate(order, signature, abi.encode(FILLER));
    }

    // function test_invalid_nonce(uint160 amount) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
    //     _initiateOrder(0, SWAPPER, amount);
    //     MockERC20(tokenToSwapInput).mint(SWAPPER, amount);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             OrderAlreadyClaimed.selector, OrderContext(OrderStatus.Claimed, address(0), FILLER, 0)
    //         )
    //     );
    //     _initiateOrder(0, SWAPPER, DEFAULT_SWAP_AMOUNT);
    // }

    function _initiateOrder(uint256 _nonce, address _swapper, uint256 _amount) internal {
        LimitOrderData memory limitOrderData = OrderDataBuilder.getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, _amount, 0, _swapper, 1 ether, 0, address(0), address(0)
        );
        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            limitOrderData,
            limitOrderReactorAddress,
            SWAPPER,
            _nonce,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, limitOrderReactor);
        bytes32 orderHash = this._getLimitOrderHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, limitOrderReactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY,
            FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH,
            orderHash,
            DOMAIN_SEPARATOR,
            limitOrderReactorAddress
        );
        limitOrderReactor.initiate(order, signature, abi.encode(FILLER));
    }

    function _getLimitOrderHash(CrossChainOrder calldata order) public pure returns (bytes32) {
        bytes32 orderDataHash = CrossChainLimitOrderType.hashOrderData(abi.decode(order.orderData, (LimitOrderData)));
        return CrossChainLimitOrderType.hash(order, orderDataHash);
    }

    function _getCurrentBalances()
        public
        view
        returns (
            uint256 swapperInputBalance,
            uint256 swapperOutputBalance,
            uint256 reactorInputBalance,
            uint256 reactorOutputBalance
        )
    {
        swapperInputBalance = MockERC20(tokenToSwapInput).balanceOf(SWAPPER);
        swapperOutputBalance = MockERC20(tokenToSwapOutput).balanceOf(SWAPPER);
        reactorInputBalance = MockERC20(tokenToSwapInput).balanceOf(limitOrderReactorAddress);
        reactorOutputBalance = MockERC20(tokenToSwapOutput).balanceOf(limitOrderReactorAddress);
    }
}
