// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { BaseReactor } from "./BaseReactor.sol";
import { LimitOrderData, CrossChainLimitOrderType } from "../libs/CrossChainLimitOrderType.sol";
import { CrossChainOrder, ResolvedCrossChainOrder, Input, Output } from "../interfaces/ISettlementContract.sol";

abstract contract LimitOrderReactor is BaseReactor {
    using CrossChainLimitOrderType for CrossChainOrder;
    using CrossChainLimitOrderType for bytes;

    function _initiate(CrossChainOrder calldata order, bytes calldata signature, bytes calldata fillerData)
        internal
        override {
            LimitOrderData memory limitData = order.orderData.decodeOrderData();


        }

    // function claim(LimitOrder calldata order, bytes calldata signature) external {
        // address filler = msg.sender;
        // (bytes32 orderHash, address orderSigner) = order.verify(signature);

        // OrderKey memory orderKey = orderKey({
        //     reactorContext: order.reactorContext,
        //     owner: orderSigner,
        //     nonce: order.nonce,
        //     inputAmount: order.inputAmount,
        //     inputToken: order.inputToken,
        //     collateral: order.collateral,
        //     localOracle: order.oracle,
        //     destinationChainIdentifier: order.destinationChainIdentifier,
        //     remoteOracle: order.remoteOracle,
        //     oracleProofHash: bytes32(0)
        // });

        // _claim(orderKey, filler);

        // emit OrderClaimed(filler, order);
    // }

    function _resolve(CrossChainOrder calldata order, bytes calldata fillerData)
        internal
        pure
        override
        returns (ResolvedCrossChainOrder memory resolvedOrder) {
        LimitOrderData memory limitData = order.orderData.decodeOrderData();

        Input memory swapperInput = Input({
            token: address(bytes20(limitData.destinationAsset)), // TODO: This is not set in the order type.
            amount: limitData.amount
        });

        Output memory swapperOutput = Output({
            token: address(bytes20(limitData.destinationAsset)),
            amount: limitData.amount,
            recipient: address(bytes20(limitData.destinationAddress)),
            chainId: uint32(uint256(limitData.destinationChainId))
        });

        Input[] memory swapperInputs = new Input[](1);
        swapperInputs[0] = swapperInput;

        Output[] memory swapperOutputs = new Output[](1);
        swapperOutputs[0] = swapperOutput;

        resolvedOrder = ResolvedCrossChainOrder({
            settlementContract: order.settlementContract,
            swapper: order.swapper,
            nonce: order.nonce,
            originChainId: order.originChainId,
            initiateDeadline: order.initiateDeadline,
            fillDeadline: order.fillDeadline,
            swapperInputs: swapperInputs,
            swapperOutputs: swapperOutputs,
            fillerOutputs: swapperOutputs
        });
    }
}
