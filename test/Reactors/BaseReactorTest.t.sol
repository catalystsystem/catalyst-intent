// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";

import { CrossChainOrderType } from "../../src/libs/CrossChainOrderType.sol";
import { BaseReactor } from "../../src/reactors/BaseReactor.sol";

import { CrossChainOrder, Input, Output } from "../../src/interfaces/ISettlementContract.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockUtils } from "../utils/MockUtils.sol";

import { CrossChainLimitOrderType, LimitOrderData } from "../../src/libs/CrossChainLimitOrderType.sol";
import { Test } from "forge-std/Test.sol";

interface Permit2DomainSeparator {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

abstract contract BaseReactorTest is Test {
    BaseReactor reactor;
    ReactorHelperConfig reactorHelperConfig;
    address tokenToSwapInput;
    address tokenToSwapOutput;
    address permit2;
    uint256 deployerKey;
    address reactorAddress;
    address SWAPPER;
    uint256 SWAPPER_PRIVATE_KEY;
    address FILLER = address(1);
    bytes32 DOMAIN_SEPARATOR;

    modifier approvedAndMinted(address _user, address _token, uint256 _amount) {
        vm.prank(_user);
        MockERC20(_token).approve(permit2, type(uint256).max);
        vm.prank(FILLER);
        MockERC20(tokenToSwapOutput).approve(reactorAddress, type(uint256).max);
        MockERC20(_token).mint(_user, _amount);
        MockERC20(tokenToSwapOutput).mint(FILLER, 20 ether);
        _;
    }

    //Will be used when we test functionalities after initialization like challenges
    modifier orderInitiaited(uint256 _nonce, address _swapper, uint256 _amount) {
        _initiateOrder(_nonce, _swapper, _amount);
        _;
    }

    constructor() {
        (SWAPPER, SWAPPER_PRIVATE_KEY) = makeAddrAndKey("swapper");
    }

    bytes32 public FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH = keccak256(
        abi.encodePacked(
            SigTransfer.PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
            CrossChainOrderType.permit2WitnessType(_orderType())
        )
    );

    function test_collect_tokens(uint256 amount) public approvedAndMinted(SWAPPER, tokenToSwapInput, amount) {
        (uint256 swapperInputBalance, uint256 reactorInputBalance) =
            MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, reactorAddress);
        _initiateOrder(0, SWAPPER, amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(reactorAddress), reactorInputBalance + amount);
    }

    function test_balances_multiple_orders(uint160 amount)
        public
        approvedAndMinted(SWAPPER, tokenToSwapInput, amount)
    {
        _initiateOrder(0, SWAPPER, amount);
        MockERC20(tokenToSwapInput).mint(SWAPPER, amount);
        (uint256 swapperInputBalance, uint256 reactorInputBalance) =
            MockUtils.getCurrentBalances(tokenToSwapInput, SWAPPER, reactorAddress);
        _initiateOrder(1, SWAPPER, amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), swapperInputBalance - amount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(reactorAddress), reactorInputBalance + amount);
    }

    function test_order_hash(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerAmount,
        uint256 challengerAmount,
        uint16 deadlineIncrement
    ) public {
        CrossChainOrder memory order =
            _getCrossOrder(inputAmount, outputAmount, fillerAmount, challengerAmount, deadlineIncrement);
        (bytes32 typeHash, bytes32 dataHash,) = this._getTypeAndDataHashes(order);
        bytes32 expected = reactor.orderHash(order);
        bytes32 actual = keccak256(
            abi.encodePacked( // TODO: bytes.concat
                typeHash,
                order.settlementContract,
                order.swapper,
                order.nonce,
                order.originChainId,
                order.initiateDeadline,
                order.fillDeadline,
                dataHash
            )
        );

        assertEq(expected, actual);
    }

    function _orderType() internal virtual returns (bytes memory);

    function _initiateOrder(uint256 _nonce, address _swapper, uint256 _amount) internal virtual;

    function _getTypeAndDataHashes(CrossChainOrder calldata order)
        public
        virtual
        returns (bytes32 typeHash, bytes32 dataHash, bytes32 orderHash);

    function _getCrossOrder(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 fillerAmount,
        uint256 challengerAmount,
        uint16 deadlineIncrement
    ) internal view virtual returns (CrossChainOrder memory order);
}
