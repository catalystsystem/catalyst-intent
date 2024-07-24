// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output } from "../interfaces/ISettlementContract.sol";

import { CrossChainOrderType } from "./CrossChainOrderType.sol";

struct DutchOrderData {
    uint32 proofDeadline;
    uint32 challengeDeadline;
    address collateralToken;
    uint256 fillerCollateralAmount;
    uint256 challengerCollateralAmount; // TODO: use factor on fillerCollateralAmount
    address localOracle;
    bytes32 remoteOracle; // TODO: figure out how to trustless.
    uint32 slopeStartingTime;
    int256 inputSlope; // The rate of input that is changing.
    int256 outputSlope; // The rate of output that is changing.
    Input input;
    Output output;
}

library CrossChainDutchOrderType {
    bytes constant DUTCH_ORDER_DATA_TYPE = abi.encodePacked(
        "DutchOrderData(",
        "uint32 proofDeadline,",
        "uint32 challengeDeadline",
        "address collateralToken,",
        "uint256 fillerCollateralAmount,",
        "uint256 challengerCollateralAmount,",
        "address localOracle,",
        "bytes32 remoteOracle,",
        "uint32 slopeStartingTime,",
        "int256 inputSlope,",
        "int256 outputSlope,",
        "Input input,",
        "Output output",
        ")",
        CrossChainOrderType.OUTPUT_TYPE_STUB,
        CrossChainOrderType.INPUT_TYPE_STUB
    );
    bytes32 constant DUTCH_ORDER_DATA_TYPE_HASH = keccak256(DUTCH_ORDER_DATA_TYPE);

    function orderTypeHash() internal pure returns (bytes32) {
        return keccak256(getOrderType());
    }

    function hashOrderDataM(DutchOrderData memory orderData) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                DUTCH_ORDER_DATA_TYPE_HASH,
                bytes4(orderData.proofDeadline),
                bytes4(orderData.challengeDeadline),
                bytes20(orderData.collateralToken),
                bytes32(orderData.fillerCollateralAmount),
                bytes32(orderData.challengerCollateralAmount),
                bytes20(orderData.localOracle),
                orderData.remoteOracle,
                bytes4(orderData.slopeStartingTime),
                bytes32(uint256(orderData.inputSlope)),
                bytes32(uint256(orderData.outputSlope)),
                CrossChainOrderType.hashInput(orderData.input),
                CrossChainOrderType.hashOutput(orderData.output)
            )
        );
    }

    function hashOrderData(DutchOrderData calldata orderData) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                DUTCH_ORDER_DATA_TYPE_HASH,
                bytes4(orderData.proofDeadline),
                bytes4(orderData.challengeDeadline),
                bytes20(orderData.collateralToken),
                bytes32(orderData.fillerCollateralAmount),
                bytes32(orderData.challengerCollateralAmount),
                bytes20(orderData.localOracle),
                orderData.remoteOracle,
                bytes4(orderData.slopeStartingTime),
                bytes32(uint256(orderData.inputSlope)),
                bytes32(uint256(orderData.outputSlope)),
                CrossChainOrderType.hashInput(orderData.input),
                CrossChainOrderType.hashOutput(orderData.output)
            )
        );
    }

    function decodeOrderData(bytes calldata orderBytes) internal pure returns (DutchOrderData memory dutchData) {
        dutchData = abi.decode(orderBytes, (DutchOrderData));
    }

    function getOrderType() internal pure returns (bytes memory) {
        return CrossChainOrderType.crossOrderType("DutchOrderData orderData", DUTCH_ORDER_DATA_TYPE);
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
     * @return orderInput The input after applying the decay function based on the time passed
     */
    function getInputAfterDecay(DutchOrderData memory dutchOrderData) internal view returns (Input memory orderInput) {
        orderInput = dutchOrderData.input;
        int256 inputSlope = dutchOrderData.inputSlope;
        if (inputSlope == 0) return orderInput; // Early exit if inputSlope == 0.

        orderInput.amount = _calcSlope(inputSlope, dutchOrderData.slopeStartingTime, orderInput.amount);
    }

    /**
     * @dev This functions calculates the the current amount the user will get in the destination chain based on the time passed.
     * The order is treated as Limit Order if the slope did not start.
     * @param dutchOrderData The order data to calculate the current output value from.
     * @return orderOutput The output after applying the decay function based on the time passed
     */
    function getOutputAfterDecay(DutchOrderData memory dutchOrderData)
        internal
        view
        returns (Output memory orderOutput)
    {
        orderOutput = dutchOrderData.output;
        int256 outputSlope = dutchOrderData.outputSlope;
        if (outputSlope == 0) return orderOutput; // Early exit if inputSlope == 0.

        orderOutput.amount = _calcSlope(outputSlope, dutchOrderData.slopeStartingTime, orderOutput.amount);
    }
}
