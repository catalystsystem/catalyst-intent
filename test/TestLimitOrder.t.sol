// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DeployLimitOrderReactor } from "../script/Reactor/DelpoyLimitOrderReactor.s.sol";

import { ReactorHelperConfig } from "../script/Reactor/HelperConfig.sol";

import { LimitOrderReactor } from "../src/reactors/LimitOrderReactor.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { SigTransfer } from "./utils/SigTransfer.sol";

import { CrossChainOrder, Input, Output } from "../src/interfaces/ISettlementContract.sol";

import { CrossChainLimitOrderType, LimitOrderData } from "../src/libs/CrossChainLimitOrderType.sol";

import { Collateral, OrderKey } from "../src/interfaces/Structs.sol";
import { LimitOrderReactor } from "../src/reactors/LimitOrderReactor.sol";

import "forge-std/Test.sol";
import { Test } from "forge-std/Test.sol";

contract TestLimitOrder is Test {
    LimitOrderReactor limitOrderReactor;
    ReactorHelperConfig reactorHelperConfig;
    address tokenToSwap;
    address permit2;
    uint256 deployerKey;
    address ALICE;
    uint256 ALICE_PRIVATE_KEY;

    function setUp() public {
        DeployLimitOrderReactor deployer = new DeployLimitOrderReactor();
        (limitOrderReactor, reactorHelperConfig) = deployer.run();
        (tokenToSwap, permit2, deployerKey) = reactorHelperConfig.currentConfig();
        (ALICE, ALICE_PRIVATE_KEY) = makeAddrAndKey("alice");

        MockERC20(tokenToSwap).mint(ALICE, 15 ether);
    }

    function test_crossOrder_to_orderKey() public {
        LimitOrderData memory limitOrderData = _getLimitOrder(tokenToSwap);
        CrossChainOrder memory order = CrossChainOrder({
            settlementContract: address(limitOrderReactor),
            swapper: ALICE,
            nonce: 0,
            originChainId: uint32(block.chainid),
            initiateDeadline: uint32(block.timestamp + 1 hours),
            fillDeadline: uint32(block.timestamp + 1 hours),
            orderData: abi.encode(limitOrderData)
        });

        OrderKey memory orderKey = limitOrderReactor.resolveKey(order, hex"");

        //Input tests
        assertEq(orderKey.inputs.length, 1);
        Input memory expectedInput = Input({ token: address(tokenToSwap), amount: uint256(1e18) });
        Input memory actualInput = orderKey.inputs[0];
        assertEq(keccak256(abi.encode(actualInput)), keccak256(abi.encode(expectedInput)));

        //Output tests
        assertEq(orderKey.outputs.length, 1);
        Output memory expectedOutput = Output({
            token: bytes32(uint256(uint160(tokenToSwap))),
            amount: uint256(0),
            recipient: bytes32(uint256(uint160(ALICE))),
            chainId: uint32(0)
        });
        Output memory actualOutput = orderKey.outputs[0];
        assertEq(keccak256(abi.encode(actualOutput)), keccak256(abi.encode(expectedOutput)));

        //Swapper test
        address actualSwapper = orderKey.swapper;
        assertEq(actualSwapper, ALICE);

        //Oracles tests
        assertEq(orderKey.localOracle, address(0));
        assertEq(orderKey.remoteOracle, bytes32(0));

        //Collateral test
        Collateral memory expectedCollateral = Collateral({
            collateralToken: tokenToSwap,
            fillerCollateralAmount: uint256(0),
            challangerCollateralAmount: uint256(0)
        });
        Collateral memory actualCollateral = orderKey.collateral;
        assertEq(keccak256(abi.encode(actualCollateral)), keccak256(abi.encode(expectedCollateral)));
    }

    function test_collect_tokens() public { }

    //TODO: Parameterize the function
    function _getLimitOrder(address _tokenToSwap) internal view returns (LimitOrderData memory limitOrderData) {
        Input memory input = Input({ token: address(tokenToSwap), amount: uint256(1e18) });
        Output memory output = Output({
            token: bytes32(uint256(uint160(_tokenToSwap))),
            amount: uint256(0),
            recipient: bytes32(uint256(uint160(ALICE))),
            chainId: uint32(0)
        });

        limitOrderData = LimitOrderData({
            proofDeadline: 0,
            collateralToken: _tokenToSwap,
            fillerCollateralAmount: uint256(0),
            challangerCollateralAmount: uint256(0),
            localOracle: address(0),
            remoteOracle: bytes32(0),
            input: input,
            output: output
        });
    }
}
