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
import { Permit2Lib } from "../src/libs/Permit2Lib.sol";
import { LimitOrderReactor } from "../src/reactors/LimitOrderReactor.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import "forge-std/Test.sol";
import { Test } from "forge-std/Test.sol";

interface Permit2DomainSeparator {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract TestLimitOrder is Test {
    LimitOrderReactor limitOrderReactor;
    ReactorHelperConfig reactorHelperConfig;
    address tokenToSwap;
    address permit2;
    uint256 deployerKey;
    address limitOrderReactorAddress;
    address ALICE;
    uint256 ALICE_PRIVATE_KEY;
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
        (tokenToSwap, permit2, deployerKey) = reactorHelperConfig.currentConfig();
        limitOrderReactorAddress = address(limitOrderReactor);

        (ALICE, ALICE_PRIVATE_KEY) = makeAddrAndKey("alice");
        vm.prank(ALICE);
        MockERC20(tokenToSwap).approve(permit2, type(uint256).max);
        MockERC20(tokenToSwap).mint(ALICE, 15 ether);
        MockERC20(tokenToSwap).mint(FILLER, 15 ether);

        DOMAIN_SEPARATOR = Permit2DomainSeparator(permit2).DOMAIN_SEPARATOR();
    }

    //TODO: Parameterize the modifier
    modifier orderInitiaited() {
        LimitOrderData memory limitOrderData = _getLimitOrder(tokenToSwap);
        CrossChainOrder memory order = _getCrossChainOrder(limitOrderData);

        bytes32 orderHash = this._getHash(order);

        OrderKey memory orderKey = limitOrderReactor.resolveKey(order, hex"");

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, limitOrderReactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            ALICE_PRIVATE_KEY, FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, limitOrderReactorAddress
        );
        limitOrderReactor.initiate(order, signature, abi.encode(FILLER));
        _;
    }

    function test_crossOrder_to_orderKey() public {
        LimitOrderData memory limitOrderData = _getLimitOrder(tokenToSwap);
        CrossChainOrder memory order = _getCrossChainOrder(limitOrderData);

        OrderKey memory orderKey = limitOrderReactor.resolveKey(order, hex"");

        //Input tests
        assertEq(orderKey.inputs.length, 1);
        Input memory expectedInput = Input({ token: tokenToSwap, amount: uint256(1e18) });
        Input memory actualInput = orderKey.inputs[0];
        assertEq(keccak256(abi.encode(actualInput)), keccak256(abi.encode(expectedInput)));

        //Output tests
        assertEq(orderKey.outputs.length, 1);
        Output memory expectedOutput = Output({
            token: bytes32(abi.encode(tokenToSwap)),
            amount: uint256(0),
            recipient: bytes32(abi.encode(ALICE)),
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
            fillerCollateralAmount: 15 ether,
            challangerCollateralAmount: 1 ether
        });
        Collateral memory actualCollateral = orderKey.collateral;
        assertEq(keccak256(abi.encode(actualCollateral)), keccak256(abi.encode(expectedCollateral)));
    }

    function test_collect_tokens() public orderInitiaited {
        assertEq(MockERC20(tokenToSwap).balanceOf(ALICE), 14 ether);
        assertEq(MockERC20(tokenToSwap).balanceOf(limitOrderReactorAddress), 1 ether);
    }

    //TODO: Parameterize the function
    function _getLimitOrder(address _tokenToSwap) internal view returns (LimitOrderData memory limitOrderData) {
        Input memory input = Input({ token: tokenToSwap, amount: uint256(1 ether) });
        Output memory output = Output({
            token: bytes32(abi.encode(_tokenToSwap)),
            amount: uint256(0),
            recipient: bytes32(abi.encode(ALICE)),
            chainId: uint32(0)
        });

        limitOrderData = LimitOrderData({
            proofDeadline: 0,
            collateralToken: _tokenToSwap,
            fillerCollateralAmount: 15 ether,
            challangerCollateralAmount: 1 ether,
            localOracle: address(0),
            remoteOracle: bytes32(0),
            input: input,
            output: output
        });
    }

    //TODO: Parameterize the function
    function _getCrossChainOrder(LimitOrderData memory limitOrderData)
        internal
        view
        returns (CrossChainOrder memory crossChainOrder)
    {
        crossChainOrder = CrossChainOrder({
            settlementContract: limitOrderReactorAddress,
            swapper: ALICE,
            nonce: 0,
            originChainId: uint32(block.chainid),
            initiateDeadline: uint32(block.timestamp + 1 hours),
            fillDeadline: uint32(block.timestamp + 1 hours),
            orderData: abi.encode(limitOrderData)
        });
    }

    function _getHash(CrossChainOrder calldata order) public pure returns (bytes32) {
        bytes32 orderDataHash = CrossChainLimitOrderType.hashOrderData(abi.decode(order.orderData, (LimitOrderData)));
        return CrossChainLimitOrderType.hash(order, orderDataHash);
    }
}
