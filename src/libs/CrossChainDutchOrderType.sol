// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output } from "../interfaces/ISettlementContract.sol";

import { StartTimeAfterEndTime } from "../interfaces/Errors.sol";
import { CROSS_CHAIN_ORDER_TYPE_STUB, INPUT_TYPE_STUB, OUTPUT_TYPE_STUB } from "./CrossChainOrderLib.sol";

struct DutchOrderData {
    uint32 proofDeadline;
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
        OUTPUT_TYPE_STUB,
        INPUT_TYPE_STUB
    );
    bytes32 constant DUTCH_ORDER_DATA_TYPE_HASH = keccak256(DUTCH_ORDER_DATA_TYPE);

    bytes constant CROSS_CHAIN_ORDER_TYPE =
        abi.encodePacked(CROSS_CHAIN_ORDER_TYPE_STUB, "DutchOrderData orderData)", DUTCH_ORDER_DATA_TYPE);

    bytes32 internal constant CROSS_CHAIN_ORDER_TYPE_HASH = keccak256(CROSS_CHAIN_ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string constant PERMIT2_WITNESS_TYPE =
        string(abi.encodePacked("CrossChainOrder witness)", CROSS_CHAIN_ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    function hash(CrossChainOrder calldata order, bytes32 orderDataHash) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked( // TODO: bytes.concat
                CROSS_CHAIN_ORDER_TYPE_HASH,
                order.settlementContract,
                order.swapper,
                order.nonce,
                order.originChainId,
                order.initiateDeadline,
                order.fillDeadline,
                orderDataHash
            )
        );
    }

    function hashInput(Input memory input) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(INPUT_TYPE_STUB, input.token, input.amount));
    }

    function hashOutput(Output memory output) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(OUTPUT_TYPE_STUB, output.token, output.amount, output.recipient, output.chainId));
    }

    // TODO: Make a bytes calldata version of this function.
    function hashOrderData(DutchOrderData memory orderData) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked( // todo: bytes.concat
                DUTCH_ORDER_DATA_TYPE_HASH,
                orderData.proofDeadline,
                orderData.collateralToken,
                orderData.fillerCollateralAmount,
                orderData.challengerCollateralAmount,
                orderData.localOracle,
                orderData.remoteOracle,
                orderData.slopeStartingTime,
                orderData.inputSlope,
                orderData.outputSlope,
                hashInput(orderData.input),
                hashOutput(orderData.output)
            )
        );
    }

    function decodeOrderData(bytes calldata orderBytes) internal pure returns (DutchOrderData memory dutchData) {
        dutchData = abi.decode(orderBytes, (DutchOrderData));
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
