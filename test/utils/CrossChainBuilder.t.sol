// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CrossChainOrder, Input } from "../../src/interfaces/ISettlementContract.sol";

import { OutputDescription } from "../../src/interfaces/Structs.sol";

import { DutchOrderData } from "../../src/libs/ordertypes/CrossChainDutchOrderType.sol";
import { LimitOrderData } from "../../src/libs/ordertypes/CrossChainLimitOrderType.sol";

//Here we can make functions that accept no order at all
//or an order but with some fields missing

library CrossChainBuilder {
    function test() public pure { }

    function getCrossChainOrder(
        LimitOrderData memory limitOrderData,
        address limitOrderReactorAddress,
        address swapper,
        uint256 nonce,
        uint32 originChainId,
        uint32 initiatedDeadline,
        uint32 fillDeadline
    ) internal pure returns (CrossChainOrder memory order) {
        order = CrossChainOrder({
            settlementContract: limitOrderReactorAddress,
            swapper: swapper,
            nonce: nonce,
            originChainId: originChainId,
            initiateDeadline: initiatedDeadline,
            fillDeadline: fillDeadline,
            orderData: abi.encode(limitOrderData)
        });
    }

    function getCrossChainOrder(
        DutchOrderData memory dutchOrderData,
        address limitOrderReactorAddress,
        address swapper,
        uint256 nonce,
        uint32 originChainId,
        uint32 initiatedDeadline,
        uint32 fillDeadline
    ) internal pure returns (CrossChainOrder memory order) {
        order = CrossChainOrder({
            settlementContract: limitOrderReactorAddress,
            swapper: swapper,
            nonce: nonce,
            originChainId: originChainId,
            initiateDeadline: initiatedDeadline,
            fillDeadline: fillDeadline,
            orderData: abi.encode(dutchOrderData)
        });
    }

    //For other reactors
    function getDutchCrossChainOrder(
        DutchOrderData memory dutchOrderData,
        address dutchAutctionReactorAddress,
        address swapper,
        uint256 nonce,
        uint32 originChainId,
        uint32 initiatedDeadline,
        uint32 fillDeadline
    ) internal pure returns (CrossChainOrder memory order) {
        order = CrossChainOrder({
            settlementContract: dutchAutctionReactorAddress,
            swapper: swapper,
            nonce: nonce,
            originChainId: originChainId,
            initiateDeadline: initiatedDeadline,
            fillDeadline: fillDeadline,
            orderData: abi.encode(dutchOrderData)
        });
    }
}
