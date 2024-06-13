// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Input, Output } from "../interfaces/ISettlementContract.sol";

import { CrossChainOrder, Input, Output, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { Collateral, OrderKey, ReactorInfo } from "../interfaces/Structs.sol";
import { CrossChainLimitOrderType, LimitOrderData } from "../libs/CrossChainLimitOrderType.sol";
import { BaseReactor } from "./BaseReactor.sol";

contract LimitOrderReactor is BaseReactor {
    using CrossChainLimitOrderType for CrossChainOrder;
    using CrossChainLimitOrderType for LimitOrderData;
    using CrossChainLimitOrderType for bytes;

    constructor(address permit2) BaseReactor(permit2) { }

    function _orderHash(CrossChainOrder calldata order) internal pure override returns (bytes32) {
        LimitOrderData memory orderData = order.orderData.decodeOrderData();
        bytes32 orderDataHash = orderData.hashOrderData();
        return order.hash(orderDataHash);
    }

    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal pure override returns (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString) {
        // Permit2 context
        LimitOrderData memory limitData = order.orderData.decodeOrderData();
        witness = limitData.hashOrderData();
        witness = order.hash(witness);
        witnessTypeString = CrossChainLimitOrderType.PERMIT2_WITNESS_TYPE;

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
                challangeDeadline: limitData.proofDeadline, // TODO: fix
                proofDeadline: limitData.proofDeadline
            }),
            swapper: order.swapper,
            nonce: uint96(order.nonce),
            collateral: Collateral({
                collateralToken: limitData.collateralToken,
                fillerCollateralAmount: limitData.fillerCollateralAmount,
                challangerCollateralAmount: limitData.challangerCollateralAmount
            }),
            originChainId: order.originChainId,
            // Proof Context
            localOracle: limitData.localOracle,
            oracleProofHash: bytes32(0),
            inputs: inputs,
            outputs: outputs
        });
    }

    function _resolve(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal view override returns (ResolvedCrossChainOrder memory resolvedOrder) {
        LimitOrderData memory limitData = order.orderData.decodeOrderData();
        address filler = abi.decode(fillerData, (address));

        Input memory swapperInput = limitData.input;

        Output memory swapperOutput = limitData.output;

        Output memory fillerOutput = Output({
            token: bytes32(uint256(uint160(limitData.input.token))),
            amount: limitData.input.amount,
            recipient: bytes32(uint256(uint160(filler))),
            chainId: uint32(block.chainid)
        });

        Input[] memory swapperInputs = new Input[](1);
        swapperInputs[0] = swapperInput;

        Output[] memory swapperOutputs = new Output[](1);
        swapperOutputs[0] = swapperOutput;

        Output[] memory fillerOutputs = new Output[](1);
        fillerOutputs[0] = fillerOutput;

        resolvedOrder = ResolvedCrossChainOrder({
            settlementContract: order.settlementContract,
            swapper: order.swapper,
            nonce: order.nonce,
            originChainId: order.originChainId,
            initiateDeadline: order.initiateDeadline,
            fillDeadline: order.fillDeadline,
            swapperInputs: swapperInputs,
            swapperOutputs: swapperOutputs,
            fillerOutputs: fillerOutputs
        });
    }
}
