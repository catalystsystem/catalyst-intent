// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { Collateral, OrderKey, ReactorInfo } from "../interfaces/Structs.sol";
import {
    CrossChainLimitMutipleOrdersType, LimitMutlipleOrdersData
} from "../libs/CrossChainLimitMultipleOrdersType.sol";
import { CrossChainOrderType } from "../libs/CrossChainOrderType.sol";

import { BaseReactor } from "./BaseReactor.sol";

contract LimitMultipleOrdersReactor is BaseReactor {
    using CrossChainOrderType for CrossChainOrder;
    using CrossChainLimitMutipleOrdersType for LimitMutlipleOrdersData;
    using CrossChainLimitMutipleOrdersType for bytes;

    constructor(address permit2) BaseReactor(permit2) { }

    function _orderHash(CrossChainOrder calldata order) internal pure override returns (bytes32) {
        LimitMutlipleOrdersData memory orderData = order.orderData.decodeOrderData();
        bytes32 orderDataHash = orderData.hashOrderDataM();
        bytes32 orderTypeHash = CrossChainLimitMutipleOrdersType.orderTypeHash();
        return order.hash(orderTypeHash, orderDataHash);
    }

    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString) {
        // Permit2 context
        LimitMutlipleOrdersData memory limitMutlipleData = order.orderData.decodeOrderData();

        witness = limitMutlipleData.hashOrderDataM();
        bytes32 orderTypeHash = CrossChainLimitMutipleOrdersType.orderTypeHash();
        witness = order.hash(orderTypeHash, witness);
        witnessTypeString = CrossChainLimitMutipleOrdersType.permit2WitnessType();

        // Set orderKey:
        orderKey = _resolveKey(order, limitMutlipleData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey) {
        LimitMutlipleOrdersData memory limitMutlipleData = order.orderData.decodeOrderData();
        return _resolveKey(order, limitMutlipleData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        LimitMutlipleOrdersData memory limitMutlipleData
    ) internal pure returns (OrderKey memory orderKey) {
        Input[] memory inputs = limitMutlipleData.inputs;
        Output[] memory outputs = limitMutlipleData.outputs;

        // Set orderKey:
        orderKey = OrderKey({
            reactorContext: ReactorInfo({
                reactor: order.settlementContract,
                // Order resolution times
                fillByDeadline: order.fillDeadline,
                challengeDeadline: limitMutlipleData.challengeDeadline,
                proofDeadline: limitMutlipleData.proofDeadline
            }),
            swapper: order.swapper,
            nonce: uint96(order.nonce),
            collateral: Collateral({
                collateralToken: limitMutlipleData.collateralToken,
                fillerCollateralAmount: limitMutlipleData.fillerCollateralAmount,
                challengerCollateralAmount: limitMutlipleData.challengerCollateralAmount
            }),
            originChainId: order.originChainId,
            // Proof Context
            localOracle: limitMutlipleData.localOracle,
            remoteOracle: limitMutlipleData.remoteOracle,
            oracleProofHash: bytes32(0),
            inputs: inputs,
            outputs: outputs
        });
    }
}
