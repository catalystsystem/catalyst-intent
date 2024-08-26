// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CrossChainOrder, Input, Output, ResolvedCrossChainOrder } from "../../interfaces/ISettlementContract.sol";
import { OrderKey, OutputDescription } from "../../interfaces/Structs.sol";

import { FillerDataLib } from "../../libs/FillerDataLib.sol";

import { ICanCollectGovernanceFee } from "../../libs/CanCollectGovernanceFee.sol";

import { ReactorAbstractions } from "./ReactorAbstractions.sol";

/**
 * @notice Resolves OrderKeys for ERC7683 compatible ResolvedCrossChainOrders.
 */
abstract contract ResolverERC7683 is ICanCollectGovernanceFee, ReactorAbstractions {
    /**
     * @notice Resolves a specific CrossChainOrder into a Catalyst specific OrderKey.
     * @dev This provides a more precise description of the cost of the order compared to the generic resolve(...).
     * @param order CrossChainOrder to resolve.
     * @param fillerData Any filler-defined data required by the settler
     * @return orderKey The full description of the order, including the inputs and outputs of the order
     */
    function resolveKey(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) external view returns (OrderKey memory orderKey) {
        return orderKey = _resolveKey(order, fillerData);
    }

    /**
     * @notice Resolves an order into an ERC-7683 compatible order struct.
     * By default relies on _resolveKey to convert OrderKey into a ResolvedCrossChainOrder
     * @dev Can be overwritten if there isn't a translation of an orderKey into resolvedOrder.
     * @param order CrossChainOrder to resolve.
     * @param  fillerData Any filler-defined data required by the settler
     * @return resolvedOrder ERC-7683 compatible order description, including the inputs and outputs of the order
     */
    function _resolve(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal view virtual returns (ResolvedCrossChainOrder memory resolvedOrder) {
        OrderKey memory orderKey = _resolveKey(order, fillerData);
        (address fillerAddress,,,,) = FillerDataLib.decode(fillerData);

        // Inputs can be taken directly from the orderKey.
        Input[] memory swapperInputs = orderKey.inputs;
        // Likewise for outputs.

        uint256 numOutputs = orderKey.outputs.length;
        Output[] memory swapperOutputs = new Output[](numOutputs);
        for (uint256 i = 0; i < numOutputs; ++i) {
            OutputDescription memory catalystOutput = orderKey.outputs[i];
            swapperOutputs[i] = Output({
                token: catalystOutput.token,
                amount: catalystOutput.amount,
                recipient: catalystOutput.recipient,
                chainId: catalystOutput.chainId
            });
        }

        // fillerOutputs are of the Output type and as a result, we can't just
        // load swapperInputs into fillerOutputs. As a result, we need to parse
        // the individual inputs and make a new struct.
        uint256 numInputs = swapperInputs.length;
        Output[] memory fillerOutputs = new Output[](numInputs);
        Output memory fillerOutput;
        unchecked {
            for (uint256 i; i < numInputs; ++i) {
                Input memory input = swapperInputs[i];
                fillerOutput = Output({
                    token: bytes32(uint256(uint160(input.token))),
                    amount: input.amount - _calcFee(input.amount),
                    recipient: bytes32(uint256(uint160(fillerAddress))),
                    chainId: uint32(block.chainid)
                });
                fillerOutputs[i] = fillerOutput;
            }
        }

        // Lastly, complete the ResolvedCrossChainOrder struct.
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

    /**
     * @notice ERC-7683: Resolves a specific CrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param order CrossChainOrder to resolve.
     * @param fillerData Any filler-defined data required by the settler
     * @return resolvedOrder ERC-7683 compatible order description, including the inputs and outputs of the order
     */
    function resolve(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) external view returns (ResolvedCrossChainOrder memory resolvedOrder) {
        return _resolve(order, fillerData);
    }
}
