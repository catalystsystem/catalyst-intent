// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ReactorBase } from "./ReactorBase.sol";
import { LimitOrderType, LimitOrder } from "../libs/LimitOrderType.sol";

contract ReactorLimitOrder is ReactorBase {
    using LimitOrderType for LimitOrder;

    // TODO: optimise
    event OrderClaimed(
        address indexed claimer,
        LimitOrder order
    );

    function claim(LimitOrder calldata order, bytes calldata signature) external {
        address filler = msg.sender;
        address orderSigner = order.verify(signature);

        OrderKey memory orderKey = orderKey({
            reactorContext: order.reactorContext,
            owner: orderSigner,
            nonce: order.nonce,
            inputAmount: order.inputAmount,
            inputToken: order.inputToken,
            collateral: order.collateral,
            localOracle: order.oracle,
            destinationChainIdentifier: order.destinationChainIdentifier,
            remoteOracle: order.remoteOracle,
            oracleProofHash: bytes32(0)
        });

        _claim(orderKey, filler);

        emit OrderClaimed(filler, order);
    }
    
}
