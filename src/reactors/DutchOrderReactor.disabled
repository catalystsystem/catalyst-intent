// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { FailedValidation, LengthsDoesNotMatch } from "../interfaces/Errors.sol";
import { IPreValidation } from "../interfaces/IPreValidation.sol";
import { CrossChainOrder, Input, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { Collateral, OrderKey, OutputDescription, ReactorInfo } from "../interfaces/Structs.sol";

import { CatalystDutchOrderData, CrossChainDutchOrderType } from "../libs/ordertypes/CrossChainDutchOrderType.sol";
import { CrossChainOrderType } from "../libs/ordertypes/CrossChainOrderType.sol";

import { BaseReactor } from "./BaseReactor.sol";

contract DutchOrderReactor is BaseReactor {
    constructor(address permit2, address owner) payable BaseReactor(permit2, owner) { }

    /** @notice This is a copy of the permittedAmounts loop. */
    function _getMaxInputs(
        CrossChainOrder calldata order
    )
        internal
        override
        pure
        returns(
            Input[] memory inputs
        )
    {
        CatalystDutchOrderData memory dutchOrderData = CrossChainDutchOrderType.decodeOrderData(order.orderData);
        uint256 slopeStartingTime = dutchOrderData.slopeStartingTime;
        uint256 initiateDeadline = order.initiateDeadline;
        uint256 maxTimePass;
        unchecked {
            // unchecked: order.initiateDeadline > dutchOrderData.slopeStartingTime
            // If initiateDeadline >= slopeStartingTime then the maximum difference is their difference.
            // If initiateDeadline < slopeStartingTime then the slope can never start.
            maxTimePass = initiateDeadline >= slopeStartingTime ? initiateDeadline - slopeStartingTime : 0;
        }
        inputs = dutchOrderData.inputs;
        uint256 numInputs = inputs.length;
        for (uint256 i = 0; i < numInputs; ++i) {
            // The permitted amount is the max of slope.
            int256 slope = dutchOrderData.inputSlopes[i];
            inputs[i].amount = slope <= 0
                ? inputs[i].amount // If slope is negative, then the max is the start.
                : inputs[i].amount + uint256(slope) * maxTimePass; // If slope is positive, then the max is
                // the end.
        }
    }

    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    )
        internal
        view
        override
        returns (
            OrderKey memory orderKey,
            uint256[] memory permittedAmounts,
            bytes32 witness,
            string memory witnessTypeString
        )
    {
        CatalystDutchOrderData memory dutchOrderData = CrossChainDutchOrderType.decodeOrderData(order.orderData);

        // Check if the number of inputs matches the number of slopes.
        uint256 numInputs = dutchOrderData.inputs.length;
        if (numInputs != dutchOrderData.inputSlopes.length) {
            revert LengthsDoesNotMatch(numInputs, dutchOrderData.inputSlopes.length);
        }

        uint256 slopeStartingTime = dutchOrderData.slopeStartingTime;
        uint256 initiateDeadline = order.initiateDeadline;
        uint256 maxTimePass;
        unchecked {
            // unchecked: order.initiateDeadline > dutchOrderData.slopeStartingTime
            // If initiateDeadline >= slopeStartingTime then the maximum difference is their difference.
            // If initiateDeadline < slopeStartingTime then the slope can never start.
            maxTimePass = initiateDeadline >= slopeStartingTime ? initiateDeadline - slopeStartingTime : 0;
        }

        // Set permitted inputs
        permittedAmounts = new uint256[](numInputs);
        for (uint256 i = 0; i < numInputs; ++i) {
            // The permitted amount is the max of slope.
            int256 slope = dutchOrderData.inputSlopes[i];
            permittedAmounts[i] = slope <= 0
                ? dutchOrderData.inputs[i].amount // If slope is negative, then the max is the start.
                : dutchOrderData.inputs[i].amount + uint256(slope) * maxTimePass; // If slope is positive, then the max is
                // the end.
        }

        // If the dutch auction is initiated before the slope starts, the order may be exclusive.
        if (slopeStartingTime > block.timestamp) {
            address verificationContract = dutchOrderData.verificationContract;
            if (verificationContract != address(0)) {
                if (!IPreValidation(verificationContract).validate(dutchOrderData.verificationContext, msg.sender)) {
                    revert FailedValidation();
                }
            }
        }

        witness = CrossChainDutchOrderType.crossOrderHash(order, dutchOrderData);
        witnessTypeString = CrossChainDutchOrderType.PERMIT2_DUTCH_ORDER_WITNESS_STRING_TYPE;

        // Set orderKey:
        orderKey = _resolveKey(order, dutchOrderData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal view override returns (OrderKey memory orderKey) {
        CatalystDutchOrderData memory dutchOrderData = CrossChainDutchOrderType.decodeOrderData(order.orderData);

        if (dutchOrderData.inputs.length != dutchOrderData.inputSlopes.length) {
            revert LengthsDoesNotMatch(dutchOrderData.inputs.length, dutchOrderData.inputSlopes.length);
        }

        return _resolveKey(order, dutchOrderData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        CatalystDutchOrderData memory dutchData
    ) internal view returns (OrderKey memory orderKey) {
        // Get the current Input (amount and token) structure based on the decay function and the time passed.
        Input[] memory inputs = CrossChainDutchOrderType.getInputsAfterDecay(dutchData);
        // Get the current Output (amount, token, and destination) structure based on the decay function and the time
        // passed.
        OutputDescription[] memory outputs = CrossChainDutchOrderType.getOutputsAfterDecay(dutchData);

        // Set orderKey:
        orderKey = OrderKey({
            reactorContext: ReactorInfo({
                reactor: order.settlementContract,
                // Order resolution times
                fillDeadline: order.fillDeadline,
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
            inputs: inputs,
            outputs: outputs
        });
    }
}
