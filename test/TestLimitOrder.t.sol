// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DeployLimitOrderReactor } from "../script/Reactor/DelpoyLimitOrderReactor.s.sol";

import { ReactorHelperConfig } from "../script/Reactor/HelperConfig.sol";

import { LimitOrderReactor } from "../src/reactors/LimitOrderReactor.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { SigTransfer } from "./utils/SigTransfer.sol";

import { CrossChainOrder, Input, Output } from "../src/interfaces/ISettlementContract.sol";

import { CrossChainLimitOrderType, LimitOrderData } from "../src/libs/CrossChainLimitOrderType.sol";

import { Collateral, OrderContext, OrderKey, OrderStatus } from "../src/interfaces/Structs.sol";
import { Permit2Lib } from "../src/libs/Permit2Lib.sol";
import { LimitOrderReactor } from "../src/reactors/LimitOrderReactor.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { InvalidDeadline, OrderAlreadyClaimed } from "../src/interfaces/Errors.sol";

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

    uint256 constant INPUT_START_AMOUNT = 15 ether;
    uint256 constant OUTPUT_START_AMOUNT = 10 ether;
    uint256 constant DEFAULT_SWAP_AMOUNT = 1 ether;

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
        vm.prank(SWAPPER);
        MockERC20(tokenToSwapInput).approve(permit2, type(uint256).max);
        MockERC20(tokenToSwapInput).mint(SWAPPER, INPUT_START_AMOUNT);
        MockERC20(tokenToSwapInput).mint(FILLER, INPUT_START_AMOUNT);
        MockERC20(tokenToSwapOutput).mint(SWAPPER, OUTPUT_START_AMOUNT);
        DOMAIN_SEPARATOR = Permit2DomainSeparator(permit2).DOMAIN_SEPARATOR();
    }

    // Will be used when we test funtionalities after initalization like challenges
    //TODO: Parameterize the modifier
    modifier orderInitiaited() {
        _initiateOrder(0, DEFAULT_SWAP_AMOUNT, SWAPPER);
        _;
    }

    /////////////////
    //Valid cases//
    /////////////////

    function test_crossOrder_to_orderKey() public {
        LimitOrderData memory limitOrderData = _getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, DEFAULT_SWAP_AMOUNT, 0, SWAPPER, 1 ether, 0, address(0), address(0)
        );
        CrossChainOrder memory order = _getCrossChainOrder(
            limitOrderData,
            SWAPPER,
            0,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        OrderKey memory orderKey = limitOrderReactor.resolveKey(order, hex"");

        //Input tests
        assertEq(orderKey.inputs.length, 1);
        Input memory expectedInput = Input({ token: tokenToSwapInput, amount: DEFAULT_SWAP_AMOUNT });
        Input memory actualInput = orderKey.inputs[0];
        assertEq(keccak256(abi.encode(actualInput)), keccak256(abi.encode(expectedInput)));

        //Output tests
        assertEq(orderKey.outputs.length, 1);
        Output memory expectedOutput = Output({
            token: bytes32(abi.encode(tokenToSwapOutput)),
            amount: uint256(0),
            recipient: bytes32(abi.encode(SWAPPER)),
            chainId: uint32(0)
        });
        Output memory actualOutput = orderKey.outputs[0];
        assertEq(keccak256(abi.encode(actualOutput)), keccak256(abi.encode(expectedOutput)));

        //Swapper test
        address actualSWAPPERer = orderKey.swapper;
        assertEq(actualSWAPPERer, SWAPPER);

        //Oracles tests
        assertEq(orderKey.localOracle, address(0));
        assertEq(orderKey.remoteOracle, bytes32(0));

        //Collateral test
        Collateral memory expectedCollateral = Collateral({
            collateralToken: tokenToSwapInput,
            fillerCollateralAmount: 1 ether,
            challangerCollateralAmount: 0
        });
        Collateral memory actualCollateral = orderKey.collateral;
        assertEq(keccak256(abi.encode(actualCollateral)), keccak256(abi.encode(expectedCollateral)));
    }

    function test_collect_tokens() public orderInitiaited {
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), INPUT_START_AMOUNT - DEFAULT_SWAP_AMOUNT);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(limitOrderReactorAddress), DEFAULT_SWAP_AMOUNT);
    }

    function test_balances_multiple_orders() public orderInitiaited {
        (uint256 swapperInputBalance,, uint256 reactorInputBalance,) = _getCurrentBalances();
        uint256 amount = 5 ether;
        _initiateOrder(1, amount, SWAPPER);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(limitOrderReactorAddress), reactorInputBalance + amount);
    }

    /////////////////
    //Invalid cases//
    /////////////////

    function test_not_enough_balance() public {
        LimitOrderData memory limitOrderData = _getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, 20 ether, 0, SWAPPER, 1 ether, 0, address(0), address(0)
        );
        CrossChainOrder memory order = _getCrossChainOrder(
            limitOrderData,
            SWAPPER,
            0,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        (bytes32 orderHash, OrderKey memory orderKey) = _getOrderKeyInfo(order);

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

    function test_not_enough_allowance() public {
        (address BOB, uint256 BOB_KEY) = makeAddrAndKey("bob");
        MockERC20(tokenToSwapInput).mint(BOB, INPUT_START_AMOUNT);
        vm.prank(BOB);
        MockERC20(tokenToSwapInput).approve(permit2, 1 ether);
        LimitOrderData memory limitOrderData =
            _getLimitOrder(tokenToSwapInput, tokenToSwapOutput, 10 ether, 0, BOB, 1 ether, 0, address(0), address(0));
        CrossChainOrder memory order = _getCrossChainOrder(
            limitOrderData,
            BOB,
            0,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        (bytes32 orderHash, OrderKey memory orderKey) = _getOrderKeyInfo(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, limitOrderReactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            BOB_KEY, FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, limitOrderReactorAddress
        );
        vm.expectRevert("TRANSFER_FROM_FAILED");
        limitOrderReactor.initiate(order, signature, abi.encode(FILLER));
    }

    function test_invalid_deadline() public {
        LimitOrderData memory limitOrderData = _getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, 20 ether, 0, SWAPPER, 1 ether, 0, address(0), address(0)
        );
        CrossChainOrder memory order = _getCrossChainOrder(
            limitOrderData, SWAPPER, uint32(block.chainid), uint32(block.timestamp), uint32(block.timestamp), 0
        );
        (bytes32 orderHash, OrderKey memory orderKey) = _getOrderKeyInfo(order);

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

    // function test_invalid_nonce() public orderInitiaited {
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             OrderAlreadyClaimed.selector, OrderContext(OrderStatus.Claimed, address(0), FILLER, 0)
    //         )
    //     );
    //     _initiateOrder(0, DEFAULT_SWAP_AMOUNT, SWAPPER);
    // }

    function _initiateOrder(uint256 _nonce, uint256 _amount, address _swapper) internal {
        LimitOrderData memory limitOrderData = _getLimitOrder(
            tokenToSwapInput, tokenToSwapOutput, _amount, 0, _swapper, 1 ether, 0, address(0), address(0)
        );
        CrossChainOrder memory order = _getCrossChainOrder(
            limitOrderData,
            SWAPPER,
            _nonce,
            uint32(block.chainid),
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 1 hours)
        );
        (bytes32 orderHash, OrderKey memory orderKey) = _getOrderKeyInfo(order);

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

    function _getLimitOrder(
        address _tokenToSwapInput,
        address _tokenToSwapOutput,
        uint256 _inputAmount,
        uint256 _outputAmount,
        address _recipient,
        uint256 _fillerAmount,
        uint256 _challengerAmount,
        address _localOracle,
        address _remoteOracle
    ) internal view returns (LimitOrderData memory limitOrderData) {
        Input memory input = Input({ token: tokenToSwapInput, amount: _inputAmount });
        Output memory output = Output({
            token: bytes32(abi.encode(_tokenToSwapOutput)),
            amount: _outputAmount,
            recipient: bytes32(abi.encode(_recipient)),
            chainId: uint32(0)
        });

        limitOrderData = LimitOrderData({
            proofDeadline: 0,
            collateralToken: _tokenToSwapInput,
            fillerCollateralAmount: _fillerAmount,
            challangerCollateralAmount: _challengerAmount,
            localOracle: _localOracle,
            remoteOracle: bytes32(abi.encode(_remoteOracle)),
            input: input,
            output: output
        });
    }

    function _getCrossChainOrder(
        LimitOrderData memory limitOrderData,
        address _swapper,
        uint256 _nonce,
        uint32 _originChainId,
        uint32 _initiatedDeadline,
        uint32 _fillDeadline
    ) internal view returns (CrossChainOrder memory crossChainOrder) {
        crossChainOrder = CrossChainOrder({
            settlementContract: limitOrderReactorAddress,
            swapper: _swapper,
            nonce: _nonce,
            originChainId: _originChainId,
            initiateDeadline: _initiatedDeadline,
            fillDeadline: _fillDeadline,
            orderData: abi.encode(limitOrderData)
        });
    }

    function _getOrderKeyInfo(CrossChainOrder memory order)
        public
        view
        returns (bytes32 orderHash, OrderKey memory orderKey)
    {
        orderHash = this._getHash(order);
        orderKey = limitOrderReactor.resolveKey(order, hex"");
    }

    function _getHash(CrossChainOrder calldata order) public pure returns (bytes32) {
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
