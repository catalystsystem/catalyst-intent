// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output } from "../interfaces/ISettlementContract.sol";

import { StartTimeAfterEndTime } from "../interfaces/Errors.sol";
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
    int256 inputSlope; // The rate of input that is increasing. Should always be positive
    int256 outputSlope; // The rate of output that is decreasing. Should always be positive
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
        "uint256 inputSlope,",
        "uint256 outputSlope,",
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
     * @dev This functions calculates the the current amount the user pay in the source chain based on the time passed.
     * The order is treated as Limit Order if the slope did not start.
     * @param dutchOrderData The order data to calculate the current input value from.
     * @return orderInput The input after applying the decay function based on the time passed
     */
    function getInputAfterDecay(DutchOrderData memory dutchOrderData) internal view returns (Input memory orderInput) {
        orderInput = dutchOrderData.input;
        // Treat it as limit order if the slope time did not start.
        if (block.timestamp >= dutchOrderData.slopeStartingTime) {
            // We know that the minimum and the maximum input are within the limits and the amount will never exceed the maximum so it is okay to do unchecked.
            //TODO: will ever there be a problem if we convert int256 to uint256 here?
            unchecked {
                orderInput.amount = orderInput.amount
                    + uint256(dutchOrderData.inputSlope) * (block.timestamp - dutchOrderData.slopeStartingTime);
            }
        }
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
        // Treat it as limit order if the slope time did not start.
        if (block.timestamp >= dutchOrderData.slopeStartingTime) {
            // We know that the minimum and the maximum input are within the limits and the amount will never exceed the maximum so it is okay to do unchecked.
            //TODO: will ever there be a problem if we convert int256 to uint256 here?
            unchecked {
                orderOutput.amount = orderOutput.amount
                    - uint256(dutchOrderData.outputSlope) * (block.timestamp - dutchOrderData.slopeStartingTime);
            }
        }
    }
}
