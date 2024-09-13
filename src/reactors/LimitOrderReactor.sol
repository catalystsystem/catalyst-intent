// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CrossChainOrder, Input, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { Collateral, OrderKey, OutputDescription, ReactorInfo } from "../interfaces/Structs.sol";
import { CrossChainLimitOrderType, CatalystLimitOrderData } from "../libs/ordertypes/CrossChainLimitOrderType.sol";
import { CrossChainOrderType } from "../libs/ordertypes/CrossChainOrderType.sol";

import { BaseReactor } from "./BaseReactor.sol";

contract LimitOrderReactor is BaseReactor {
    constructor(address permit2, address owner) BaseReactor(permit2, owner) { }

    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey, uint256[] memory permittedAmounts, bytes32 witness, string memory witnessTypeString) {
        // Permit2 context
        CatalystLimitOrderData memory limitOrderData = CrossChainLimitOrderType.decodeOrderData(order.orderData);
        // Set permitted inputs
        uint256 numInputs = limitOrderData.inputs.length;
        permittedAmounts = new uint256[](numInputs);
        for (uint256 i = 0; i < numInputs; ++i) {
            permittedAmounts[i] = limitOrderData.inputs[i].amount;
        }

        witness = CrossChainLimitOrderType.crossOrderHash(order, limitOrderData);
        witnessTypeString = CrossChainLimitOrderType.PERMIT2_LIMIT_ORDER_WITNESS_STRING_TYPE;

        // Set orderKey:
        orderKey = _resolveKey(order, limitOrderData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey) {
        CatalystLimitOrderData memory limitData = CrossChainLimitOrderType.decodeOrderData(order.orderData);
        return _resolveKey(order, limitData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        CatalystLimitOrderData memory limitData
    ) internal pure returns (OrderKey memory orderKey) {
        Input[] memory inputs = limitData.inputs;
        OutputDescription[] memory outputs = limitData.outputs;

        // Set orderKey:
        orderKey = OrderKey({
            reactorContext: ReactorInfo({
                reactor: order.settlementContract,
                // Order resolution times
                fillDeadline: order.fillDeadline,
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
            inputs: inputs,
            outputs: outputs
        });
    }
}
