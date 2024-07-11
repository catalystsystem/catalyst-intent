// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { Collateral, OrderKey, ReactorInfo } from "../interfaces/Structs.sol";
import {
    CrossChainLimitMultipleOrdersType, LimitMultipleOrdersData
} from "../libs/CrossChainLimitMultipleOrdersType.sol";
import { CrossChainOrderType } from "../libs/CrossChainOrderType.sol";

import { BaseReactor } from "./BaseReactor.sol";

contract LimitMultipleOrdersReactor is BaseReactor {
    using CrossChainOrderType for CrossChainOrder;
    using CrossChainLimitMultipleOrdersType for LimitMultipleOrdersData;
    using CrossChainLimitMultipleOrdersType for bytes;

    constructor(address permit2) BaseReactor(permit2) { }

    function _orderHash(CrossChainOrder calldata order) internal pure override returns (bytes32) {
        LimitMultipleOrdersData memory orderData = order.orderData.decodeOrderData();
        bytes32 orderDataHash = orderData.hashOrderDataM();
        bytes32 orderTypeHash = CrossChainLimitMultipleOrdersType.orderTypeHash();
        return order.hash(orderTypeHash, orderDataHash);
    }

    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString) {
        // Permit2 context
        LimitMultipleOrdersData memory limitMultipleData = order.orderData.decodeOrderData();

        witness = limitMultipleData.hashOrderDataM();
        bytes32 orderTypeHash = CrossChainLimitMultipleOrdersType.orderTypeHash();
        witness = order.hash(orderTypeHash, witness);
        witnessTypeString = CrossChainOrderType.permit2WitnessType(CrossChainLimitMultipleOrdersType.getOrderType());

        // Set orderKey:
        orderKey = _resolveKey(order, limitMultipleData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey) {
        LimitMultipleOrdersData memory limitMultipleData = order.orderData.decodeOrderData();
        return _resolveKey(order, limitMultipleData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        LimitMultipleOrdersData memory limitMultipleData
    ) internal pure returns (OrderKey memory orderKey) {
        Input[] memory inputs = limitMultipleData.inputs;
        Output[] memory outputs = limitMultipleData.outputs;

        // Set orderKey:
        orderKey = OrderKey({
            reactorContext: ReactorInfo({
                reactor: order.settlementContract,
                // Order resolution times
                fillByDeadline: order.fillDeadline,
                challengeDeadline: limitMultipleData.challengeDeadline,
                proofDeadline: limitMultipleData.proofDeadline
            }),
            swapper: order.swapper,
            nonce: uint96(order.nonce),
            collateral: Collateral({
                collateralToken: limitMultipleData.collateralToken,
                fillerCollateralAmount: limitMultipleData.fillerCollateralAmount,
                challengerCollateralAmount: limitMultipleData.challengerCollateralAmount
            }),
            originChainId: order.originChainId,
            // Proof Context
            localOracle: limitMultipleData.localOracle,
            remoteOracle: limitMultipleData.remoteOracle,
            oracleProofHash: bytes32(0),
            inputs: inputs,
            outputs: outputs
        });
    }
}
