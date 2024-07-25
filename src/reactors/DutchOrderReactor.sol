// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { Collateral, OrderKey, ReactorInfo } from "../interfaces/Structs.sol";

import { CrossChainDutchOrderType, DutchOrderData } from "../libs/CrossChainDutchOrderType.sol";
import { CrossChainOrderType } from "../libs/CrossChainOrderType.sol";

import { BaseReactor } from "./BaseReactor.sol";

contract DutchOrderReactor is BaseReactor {
    using CrossChainOrderType for CrossChainOrder;
    using CrossChainDutchOrderType for DutchOrderData;
    using CrossChainDutchOrderType for bytes;

    constructor(address permit2) BaseReactor(permit2) { }

    function _orderHash(CrossChainOrder calldata order) internal pure override returns (bytes32) {
        DutchOrderData memory orderData = order.orderData.decodeOrderData();
        bytes32 orderDataHash = orderData.hashOrderDataM();
        bytes32 orderTypeHash = CrossChainDutchOrderType.orderTypeHash();
        return order.hash(orderTypeHash, orderDataHash);
    }

    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal view override returns (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString) {
        // Permit2 context
        DutchOrderData memory dutchData = order.orderData.decodeOrderData();

        witness = dutchData.hashOrderDataM();
        bytes32 orderTypeHash = CrossChainDutchOrderType.orderTypeHash();
        witness = order.hash(orderTypeHash, witness);
        witnessTypeString = CrossChainOrderType.permit2WitnessType(CrossChainDutchOrderType.getOrderType());

        // Set orderKey:
        orderKey = _resolveKey(order, dutchData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal view override returns (OrderKey memory orderKey) {
        DutchOrderData memory dutchData = order.orderData.decodeOrderData();
        return _resolveKey(order, dutchData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        DutchOrderData memory dutchData
    ) internal view returns (OrderKey memory orderKey) {
        // The Dutch auction order type has a single Input and Output
        Input[] memory inputs = new Input[](1);
        Output[] memory outputs = new Output[](1);

        // Get the current Input(amount and token) structure based on the decay function and the time passed.
        inputs[0] = dutchData.getInputAfterDecay();
        // Get the current Output(amount,token and destination) structure based on the decay function and the time passed.
        outputs[0] = dutchData.getOutputAfterDecay();

        // Set orderKey:
        orderKey = OrderKey({
            reactorContext: ReactorInfo({
                reactor: order.settlementContract,
                // Order resolution times
                fillByDeadline: order.fillDeadline,
                challengeDeadline: dutchData.challengeDeadline,
                proofDeadline: dutchData.proofDeadline
            }),
            swapper: order.swapper,
            nonce: uint96(order.nonce),
            collateral: Collateral({
                collateralToken: dutchData.collateralToken,
                fillerCollateralAmount: dutchData.fillerCollateralAmount,
                challengerCollateralAmount: dutchData.challengerCollateralAmount
            }),
            originChainId: order.originChainId,
            // Proof Context
            localOracle: dutchData.localOracle,
            remoteOracle: dutchData.remoteOracle,
            oracleProofHash: bytes32(0),
            inputs: inputs,
            outputs: outputs
        });
    }
}
