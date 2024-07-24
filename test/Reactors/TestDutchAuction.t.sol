// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DeployDutchOrderReactor } from "../../script/Reactor/DeployDutchOrderReactor.s.sol";
import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";

import { CrossChainOrder, Input, Output } from "../../src/interfaces/ISettlementContract.sol";
import { DutchOrderReactor } from "../../src/reactors/DutchOrderReactor.sol";

import { CrossChainDutchOrderType, DutchOrderData } from "../../src/libs/CrossChainDutchOrderType.sol";
import { CrossChainOrderType } from "../../src/libs/CrossChainOrderType.sol";

import { BaseReactorTest, Permit2DomainSeparator } from "./BaseReactorTest.t.sol";

import { Collateral, OrderContext, OrderKey, OrderStatus } from "../../src/interfaces/Structs.sol";
import { CrossChainBuilder } from "../utils/CrossChainBuilder.t.sol";

import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";
import { OrderDataBuilder } from "../utils/OrderDataBuilder.t.sol";

import { OrderKeyInfo } from "../utils/OrderKeyInfo.t.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

contract TestDutchAuction is BaseReactorTest {
    using CrossChainDutchOrderType for DutchOrderData;
    using CrossChainOrderType for CrossChainOrder;
    using SigTransfer for ISignatureTransfer.PermitBatchTransferFrom;

    function setUp() public {
        DeployDutchOrderReactor deployer = new DeployDutchOrderReactor();
        (reactor, reactorHelperConfig) = deployer.run();
        (tokenToSwapInput, tokenToSwapOutput, permit2, deployerKey) = reactorHelperConfig.currentConfig();
        reactorAddress = address(reactor);
        DOMAIN_SEPARATOR = Permit2DomainSeparator(permit2).DOMAIN_SEPARATOR();
    }

    function _orderType() internal virtual override returns (bytes memory) {
        return CrossChainDutchOrderType.getOrderType();
    }

    function _initiateOrder(uint256 _nonce, address _swapper, uint256 _amount, address fillerSender) internal virtual override {
        CrossChainOrder memory order = _getCrossOrder(_amount, 0, _swapper, 1 ether, 0, 1, 5, 10, 11, _nonce);

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        (,, bytes32 orderHash) = this._getTypeAndDataHashes(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) = Permit2Lib.toPermit(orderKey, reactorAddress);

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, FULL_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, reactorAddress
        );
        vm.prank(fillerSender);
        reactor.initiate(order, signature, fillerData);
    }

    function _getTypeAndDataHashes(CrossChainOrder calldata order)
        public
        virtual
        override
        returns (bytes32 typeHash, bytes32 dataHash, bytes32 orderHash)
    {
        DutchOrderData memory dutchOrderData = abi.decode(order.orderData, (DutchOrderData));
        typeHash = CrossChainDutchOrderType.orderTypeHash();
        dataHash = dutchOrderData.hashOrderDataM();
        orderHash = order.hash(typeHash, dataHash);
    }

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
    ) internal view virtual override returns (CrossChainOrder memory order) {
        DutchOrderData memory dutchOrderData = OrderDataBuilder.getDutchOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            recipient,
            tokenToSwapOutput,
            fillerAmount,
            challengerAmount, // TODO: Is this collateral amount?
            proofDeadline,
            challengeDeadline,
            address(0),
            address(0)
        );

        order = CrossChainBuilder.getCrossChainOrder(
            dutchOrderData,
            reactorAddress,
            recipient,
            nonce,
            uint32(block.chainid),
            uint32(initiateDeadline),
            uint32(fillDeadline)
        );
    }
    //TODO: add private functions to set slopes for dutch order and  test the dutch order when we fuzz the slopes
}
