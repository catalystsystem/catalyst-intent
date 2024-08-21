// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CrossChainOrder, Input, Output } from "../../interfaces/ISettlementContract.sol";

import { OutputDescription } from "../../interfaces/Structs.sol";

import { CrossChainOrderType } from "./CrossChainOrderType.sol";

struct DutchOrderData {
    bytes32 verificationContext;
    address verificationContract;
    uint32 proofDeadline;
    uint32 challengeDeadline;
    address collateralToken;
    uint256 fillerCollateralAmount;
    uint256 challengerCollateralAmount;
    address localOracle;
    uint32 slopeStartingTime;
    int256[] inputSlopes; // Input rate of change.
    int256[] outputSlopes; // Output rate of change.
    Input[] inputs;
    OutputDescription[] outputs;
}

library CrossChainDutchOrderType {
    error LengthsDoesNotMatch(uint256, uint256);

    bytes constant DUTCH_ORDER_DATA_TYPE = abi.encodePacked(
        "CatalystDutchOrderData(",
        "bytes32 verificationContext,",
        "address verificationContract,",
        "uint32 proofDeadline,",
        "uint32 challengeDeadline,",
        "address collateralToken,",
        "uint256 fillerCollateralAmount,",
        "uint256 challengerCollateralAmount,",
        "address localOracle,",
        "uint32 slopeStartingTime,",
        "int256[] inputSlopes,",
        "int256[] outputSlopes,",
        "Input[] inputs,",
        "OutputDescription[] outputs",
        ")",
        CrossChainOrderType.INPUT_TYPE_STUB,
        CrossChainOrderType.OUTPUT_TYPE_STUB
    );

    bytes constant DUTCH_ORDER_DATA_TYPE_ONLY = abi.encodePacked(
        "CatalystDutchOrderData(",
        "bytes32 verificationContext,",
        "address verificationContract,",
        "uint32 proofDeadline,",
        "uint32 challengeDeadline,",
        "address collateralToken,",
        "uint256 fillerCollateralAmount,",
        "uint256 challengerCollateralAmount,",
        "address localOracle,",
        "uint32 slopeStartingTime,",
        "int256[] inputSlopes,",
        "int256[] outputSlopes,",
        "Input[] inputs,",
        "OutputDescription[] outputs",
        ")"
    );

    bytes constant CROSS_DUTCH_ORDER_TYPE_STUB = abi.encodePacked(
        "CrossChainOrder(",
        "address settlementContract,",
        "address swapper,",
        "uint256 nonce,",
        "uint32 originChainId,",
        "uint32 initiateDeadline,",
        "uint32 fillDeadline,",
        "CatalystDutchOrderData orderData",
        ")"
    );
    bytes32 constant DUTCH_ORDER_DATA_TYPE_HASH = keccak256(DUTCH_ORDER_DATA_TYPE);

    function decodeOrderData(bytes calldata orderBytes) internal pure returns (DutchOrderData memory dutchData) {
        dutchData = abi.decode(orderBytes, (DutchOrderData));
    }

    function hashOrderDataM(DutchOrderData memory orderData) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                bytes.concat(
                    DUTCH_ORDER_DATA_TYPE_HASH,
                    bytes32(orderData.verificationContext),
                    bytes32(uint256(uint160(orderData.verificationContract))),
                    bytes32(uint256(orderData.proofDeadline)),
                    bytes32(uint256(orderData.challengeDeadline)),
                    bytes32(uint256(uint160(orderData.collateralToken))),
                    bytes32(orderData.fillerCollateralAmount),
                    bytes32(orderData.challengerCollateralAmount),
                    bytes32(uint256(uint160(orderData.localOracle))),
                    bytes32(uint256(orderData.slopeStartingTime)),
                    keccak256(abi.encodePacked(orderData.inputSlopes)),
                    keccak256(abi.encodePacked(orderData.outputSlopes)),
                    CrossChainOrderType.hashInputs(orderData.inputs),
                    CrossChainOrderType.hashOutputs(orderData.outputs)
                )
            )
        );
    }

    function hashOrderData(DutchOrderData calldata orderData) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                DUTCH_ORDER_DATA_TYPE_HASH,
                bytes32(orderData.verificationContext),
                bytes32(uint256(uint160(orderData.verificationContract))),
                bytes32(uint256(orderData.proofDeadline)),
                bytes32(uint256(orderData.challengeDeadline)),
                bytes32(uint256(uint160(orderData.collateralToken))),
                bytes32(orderData.fillerCollateralAmount),
                bytes32(orderData.challengerCollateralAmount),
                bytes32(uint256(uint160(orderData.localOracle))),
                bytes32(uint256(orderData.slopeStartingTime)),
                keccak256(abi.encodePacked(orderData.inputSlopes)),
                keccak256(abi.encodePacked(orderData.outputSlopes)),
                CrossChainOrderType.hashInputs(orderData.inputs),
                CrossChainOrderType.hashOutputs(orderData.outputs)
            )
        );
    }

    function crossOrderHash(CrossChainOrder calldata order) internal pure returns (bytes32) {
        DutchOrderData memory dutchOrderData = decodeOrderData(order.orderData);
        return keccak256(
            abi.encode(
                keccak256(abi.encodePacked(CROSS_DUTCH_ORDER_TYPE_STUB, DUTCH_ORDER_DATA_TYPE)),
                order.settlementContract,
                order.swapper,
                order.nonce,
                order.originChainId,
                order.initiateDeadline,
                order.fillDeadline,
                hashOrderDataM(dutchOrderData)
            )
        );
    }

    function permit2WitnessType() internal pure returns (string memory permit2WitnessTypeString) {
        permit2WitnessTypeString = string(
            abi.encodePacked(
                "CrossChainOrder witness)",
                DUTCH_ORDER_DATA_TYPE_ONLY,
                CROSS_DUTCH_ORDER_TYPE_STUB,
                CrossChainOrderType.INPUT_TYPE_STUB,
                CrossChainOrderType.OUTPUT_TYPE_STUB,
                CrossChainOrderType.TOKEN_PERMISSIONS_TYPE
            )
        );
    }

    /**
     * @notice Computes the slope for a simple dutch order.
     * @dev For inputs, slope should generally be positive where for outputs it should be negative.
     * However, no limitations are applied to how orders are structured.
     * @param slope Change in amount per second.
     * @param startingTime Timestamp for when the order started. Is compared against block.timestamp.
     * @param startingAmount Initial amount.
     * @return currentAmount Amount after the slope has been applied.
     */
    function _calcSlope(
        int256 slope,
        uint256 startingTime,
        uint256 startingAmount
    ) internal view returns (uint256 currentAmount) {
        uint256 currTime = block.timestamp;
        if (currTime <= startingTime) return currentAmount = startingAmount;

        uint256 timePassed;
        unchecked {
            // It is known: currTime > startingTime
            timePassed = currTime - startingTime;
        }
        // If slope > 0, then add delta (slope * time). If slope < 0 then subtract delta (slope * time).
        currentAmount =
            slope > 0 ? startingAmount + uint256(slope) * timePassed : startingAmount - uint256(-slope) * timePassed;
    }

    /**
     * @dev This functions calculates the the current amount the user pay in the source chain based on the time passed.
     * The order is treated as Limit Order if the slope did not start.
     * @param dutchOrderData The order data to calculate the current input value from.
     * @return orderInputs The input after applying the decay function based on the time passed
     */
    function getInputsAfterDecay(DutchOrderData memory dutchOrderData)
        internal
        view
        returns (Input[] memory orderInputs)
    {
        orderInputs = dutchOrderData.inputs;
        int256[] memory inputSlopes = dutchOrderData.inputSlopes;
        // Validate that their lengths are equal.
        uint256 numInputs = orderInputs.length;
        if (numInputs != inputSlopes.length) revert LengthsDoesNotMatch(numInputs, inputSlopes.length);
        unchecked {
            for (uint256 i; i < numInputs; ++i) {
                int256 inputSlope = inputSlopes[i];
                if (inputSlope == 0) continue;

                orderInputs[i].amount = _calcSlope(inputSlope, dutchOrderData.slopeStartingTime, orderInputs[i].amount);
            }
        }
    }

    /**
     * @dev This functions calculates the the current amount the user will get in the destination chain based on the time passed.
     * The order is treated as Limit Order if the slope did not start.
     * @param dutchOrderData The order data to calculate the current output value from.
     * @return orderOutputs The output after applying the decay function based on the time passed
     */
    function getOutputsAfterDecay(DutchOrderData memory dutchOrderData)
        internal
        view
        returns (OutputDescription[] memory orderOutputs)
    {
        orderOutputs = dutchOrderData.outputs;
        int256[] memory outputSlopes = dutchOrderData.outputSlopes;
        // Validate that their lengths are equal.
        uint256 numOutputs = orderOutputs.length;
        if (numOutputs != outputSlopes.length) revert LengthsDoesNotMatch(numOutputs, outputSlopes.length);

        unchecked {
            for (uint256 i; i < numOutputs; ++i) {
                int256 outputSlope = outputSlopes[i];
                if (outputSlope == 0) continue;

                orderOutputs[i].amount =
                    _calcSlope(outputSlope, dutchOrderData.slopeStartingTime, orderOutputs[i].amount);
            }
        }
    }
}
