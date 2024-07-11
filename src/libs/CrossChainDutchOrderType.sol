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
    uint256 inputSlope; // The rate of input that is increasing. Should always be positive
    uint256 outputSlope; // The rate of output that is decreasing. Should always be positive
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
                bytes32(orderData.inputSlope),
                bytes32(orderData.outputSlope),
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
                bytes32(orderData.inputSlope),
                bytes32(orderData.outputSlope),
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

    //Get input amount after decay
    function getInputAfterDecay(DutchOrderData memory dutchOrderData) internal view returns (Input memory orderInput) {
        if (block.timestamp <= dutchOrderData.slopeStartingTime) revert StartTimeAfterEndTime();

        orderInput = dutchOrderData.input;

        unchecked {
            orderInput.amount =
                orderInput.amount + dutchOrderData.inputSlope * (block.timestamp - dutchOrderData.slopeStartingTime);
        }
    }

    //Get output amount after decay
    function getOutputAfterDecay(DutchOrderData memory dutchOrderData)
        internal
        view
        returns (Output memory orderOutput)
    {
        // TODO: Replace with max value for flat line before slopStaringTime?
        if (block.timestamp <= dutchOrderData.slopeStartingTime) revert StartTimeAfterEndTime();

        orderOutput = dutchOrderData.output;

        unchecked {
            orderOutput.amount =
                orderOutput.amount - dutchOrderData.outputSlope * (block.timestamp - dutchOrderData.slopeStartingTime);
        }
    }
}
