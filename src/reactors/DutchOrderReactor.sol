// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FailedValidation } from "../interfaces/Errors.sol";
import { IPreValidation } from "../interfaces/IPreValidation.sol";
import { CrossChainOrder, Input, Output, ResolvedCrossChainOrder } from "../interfaces/ISettlementContract.sol";
import { Collateral, OrderKey, ReactorInfo } from "../interfaces/Structs.sol";

import { CrossChainDutchOrderType, DutchOrderData } from "../libs/ordertypes/CrossChainDutchOrderType.sol";
import { CrossChainOrderType } from "../libs/ordertypes/CrossChainOrderType.sol";

import { BaseReactor } from "./BaseReactor.sol";

contract DutchOrderReactor is BaseReactor {
    constructor(address permit2) BaseReactor(permit2) { }

    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal view override returns (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString) {
        // Permit2 context
        DutchOrderData memory dutchData = CrossChainDutchOrderType.decodeOrderData(order.orderData);

        // If the dutch auction is initiated before the slope starts, the order may be exclusive.
        uint256 lockTime = dutchData.slopeStartingTime;
        if (lockTime > block.timestamp) {
            address verificationContract = dutchData.verificationContract;
            if (verificationContract != address(0)) {
                if (!IPreValidation(verificationContract).validate(dutchData.verificationContext, msg.sender)) {
                    revert FailedValidation();
                }
            }
        }

        witness = CrossChainDutchOrderType.hashOrderDataM(dutchData);
        bytes32 orderTypeHash = CrossChainDutchOrderType.orderTypeHash();
        witness = CrossChainOrderType.hash(order, orderTypeHash, witness);
        witnessTypeString = CrossChainOrderType.permit2WitnessType(CrossChainDutchOrderType.getOrderType());

        // Set orderKey:
        orderKey = _resolveKey(order, dutchData);
    }

    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata /* fillerData */
    ) internal view override returns (OrderKey memory orderKey) {
        DutchOrderData memory dutchData = CrossChainDutchOrderType.decodeOrderData(order.orderData);
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
        inputs[0] = CrossChainDutchOrderType.getInputAfterDecay(dutchData);
        // Get the current Output(amount,token and destination) structure based on the decay function and the time passed.
        outputs[0] = CrossChainDutchOrderType.getOutputAfterDecay(dutchData);

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
