// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { Collateral, OrderKey, ReactorInfo } from "../interfaces/Structs.sol";
import { CrossChainLimitOrderType, LimitOrderData } from "../libs/CrossChainLimitOrderType.sol";
import { CrossChainOrderType } from "../libs/CrossChainOrderType.sol";

import { BaseReactor } from "./BaseReactor.sol";

contract LimitOrderReactor is BaseReactor {
    using CrossChainOrderType for CrossChainOrder;
    using CrossChainLimitOrderType for LimitOrderData;
    using CrossChainLimitOrderType for bytes;

    constructor(address permit2) BaseReactor(permit2) { }

    function _orderHash(CrossChainOrder calldata order) internal pure override returns (bytes32) {
        LimitOrderData memory orderData = order.orderData.decodeOrderData();
        bytes32 orderDataHash = orderData.hashOrderDataM();
        bytes32 orderTypeHash = CrossChainLimitOrderType.orderTypeHash();
        return order.hash(orderTypeHash, orderDataHash);
    }

    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString) {
        // Permit2 context
        LimitOrderData memory limitData = order.orderData.decodeOrderData();

        witness = limitData.hashOrderDataM();
        bytes32 orderTypeHash = CrossChainLimitOrderType.orderTypeHash();
        witness = order.hash(orderTypeHash, witness);
        witnessTypeString = CrossChainLimitOrderType.permit2WitnessType();

        // Set orderKey:
        orderKey = _resolveKey(order, limitData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey) {
        LimitOrderData memory limitData = order.orderData.decodeOrderData();
        return _resolveKey(order, limitData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        LimitOrderData memory limitData
    ) internal pure returns (OrderKey memory orderKey) {
        Input[] memory inputs = new Input[](1);
        Output[] memory outputs = new Output[](1);

        inputs[0] = limitData.input;
        outputs[0] = limitData.output;

        // Set orderKey:
        orderKey = OrderKey({
            reactorContext: ReactorInfo({
                reactor: order.settlementContract,
                // Order resolution times
                fillByDeadline: order.fillDeadline,
                challengeDeadline: limitData.challengeDeadline,
                proofDeadline: limitData.proofDeadline
            }),
            swapper: order.swapper,
            nonce: uint96(order.nonce),
            collateral: Collateral({
                collateralToken: limitData.collateralToken,
                fillerCollateralAmount: limitData.fillerCollateralAmount,
                challengerCollateralAmount: limitData.challengerCollateralAmount
            }),
            originChainId: order.originChainId,
            // Proof Context
            localOracle: limitData.localOracle,
            remoteOracle: limitData.remoteOracle,
            oracleProofHash: bytes32(0),
            inputs: inputs,
            outputs: outputs
        });
    }
}
