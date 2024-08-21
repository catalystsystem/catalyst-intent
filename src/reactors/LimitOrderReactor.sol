// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { Collateral, OrderKey, OutputDescription, ReactorInfo } from "../interfaces/Structs.sol";
import { CrossChainLimitOrderType, LimitOrderData } from "../libs/ordertypes/CrossChainLimitOrderType.sol";
import { CrossChainOrderType } from "../libs/ordertypes/CrossChainOrderType.sol";

import { BaseReactor } from "./BaseReactor.sol";

contract LimitOrderReactor is BaseReactor {
    constructor(address permit2, address owner) BaseReactor(permit2, owner) { }

    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString) {
        // Permit2 context
        LimitOrderData memory limitData = CrossChainLimitOrderType.decodeOrderData(order.orderData);

        witness = CrossChainLimitOrderType.crossOrderHash(order);
        witnessTypeString = CrossChainLimitOrderType.permit2WitnessType();

        // Set orderKey:
        orderKey = _resolveKey(order, limitData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey) {
        LimitOrderData memory limitData = CrossChainLimitOrderType.decodeOrderData(order.orderData);
        return _resolveKey(order, limitData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        LimitOrderData memory limitData
    ) internal pure returns (OrderKey memory orderKey) {
        Input[] memory inputs = limitData.inputs;
        OutputDescription[] memory outputs = limitData.outputs;

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
            oracleProofHash: bytes32(0),
            inputs: inputs,
            outputs: outputs
        });
    }
}
