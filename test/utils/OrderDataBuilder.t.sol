// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Input, Output } from "../../src/interfaces/ISettlementContract.sol";

import { FillerDataLib } from "../../src/libs/FillerDataLib.sol";
import { DutchOrderData } from "../../src/libs/ordertypes/CrossChainDutchOrderType.sol";
import { LimitOrderData } from "../../src/libs/ordertypes/CrossChainLimitOrderType.sol";

library OrderDataBuilder {
    function test() public pure { }

    function getLimitOrder(
        address tokenToSwapInput,
        address tokenToSwapOutput,
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient,
        address collateralToken,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        uint32 proofDeadline,
        uint32 challengeDeadline,
        address localOracle,
        address remoteOracle
    ) internal view returns (LimitOrderData memory limitOrderData) {
        Input[] memory inputs = new Input[](1);
        inputs[0] = getInput(tokenToSwapInput, inputAmount);
        Output[] memory outputs = new Output[](1);
        outputs[0] = getOutput(tokenToSwapOutput, outputAmount, recipient, uint32(block.chainid));

        limitOrderData = LimitOrderData({
            proofDeadline: proofDeadline,
            challengeDeadline: challengeDeadline,
            collateralToken: collateralToken,
            fillerCollateralAmount: fillerCollateralAmount,
            challengerCollateralAmount: challengerCollateralAmount,
            localOracle: localOracle,
            remoteOracle: bytes32(uint256(uint160(remoteOracle))),
            inputs: inputs,
            outputs: outputs
        });
    }

    function getLimitMultipleOrders(
        address tokenToSwapInput,
        address tokenToSwapOutput,
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient,
        address collateralToken,
        uint256 fillerCollateralAmount,
        uint256 challengerCollateralAmount,
        uint32 proofDeadline,
        uint32 challengeDeadline,
        address localOracle,
        address remoteOracle,
        uint256 length
    ) internal view returns (LimitOrderData memory limitOrderData) {
        Input[] memory inputs = getInputs(tokenToSwapInput, inputAmount, length);
        Output[] memory outputs = getOutputs(tokenToSwapOutput, outputAmount, recipient, uint32(block.chainid), length);

        limitOrderData = LimitOrderData({
            proofDeadline: proofDeadline,
            challengeDeadline: challengeDeadline,
            collateralToken: collateralToken,
            fillerCollateralAmount: fillerCollateralAmount,
            challengerCollateralAmount: challengerCollateralAmount,
            localOracle: localOracle,
            remoteOracle: bytes32(uint256(uint160(remoteOracle))),
            inputs: inputs,
            outputs: outputs
        });
    }

    function getDutchOrder(
        address tokenToSwapInput,
        address tokenToSwapOutput,
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient,
        address collateralToken,
        uint256 fillerAmount,
        uint256 challengerAmount,
        uint32 proofDeadline,
        uint32 challengeDeadline,
        address localOracle,
        address remoteOracle,
        bytes32 verificationContext,
        address verificationContract
    ) internal view returns (DutchOrderData memory dutchOrderData) {
        Input[] memory inputs = new Input[](1);
        inputs[0] = getInput(tokenToSwapInput, inputAmount);
        Output[] memory outputs = new Output[](1);
        outputs[0] = getOutput(tokenToSwapOutput, outputAmount, recipient, uint32(block.chainid));

        int256[] memory inputSlopes = new int256[](1);
        int256[] memory outputSlopes = new int256[](1);

        dutchOrderData = DutchOrderData({
            verificationContext: verificationContext,
            verificationContract: verificationContract,
            proofDeadline: proofDeadline,
            challengeDeadline: challengeDeadline,
            collateralToken: collateralToken,
            fillerCollateralAmount: fillerAmount,
            challengerCollateralAmount: challengerAmount,
            localOracle: localOracle,
            slopeStartingTime: 0,
            inputSlopes: inputSlopes,
            outputSlopes: outputSlopes,
            remoteOracle: bytes32(abi.encode(remoteOracle)),
            inputs: inputs,
            outputs: outputs
        });
    }

    function getInput(address tokenToSwapInput, uint256 inputAmount) internal pure returns (Input memory input) {
        input = Input({ token: tokenToSwapInput, amount: inputAmount });
    }

    function getOutput(
        address tokenToSwapOutput,
        uint256 outputAmount,
        address recipient,
        uint32 chainId
    ) internal pure returns (Output memory output) {
        output = Output({
            token: bytes32(abi.encode(tokenToSwapOutput)),
            amount: outputAmount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: chainId
        });
    }

    function getOutputs(
        address tokenToSwapOutput,
        uint256 outputAmount,
        address recipient,
        uint32 chainId,
        uint256 length
    ) internal pure returns (Output[] memory outputs) {
        outputs = new Output[](length);
        for (uint256 i; i < length; ++i) {
            outputs[i] = getOutput(tokenToSwapOutput, outputAmount, recipient, chainId);
        }
    }

    function getInputs(
        address tokenToSwapInput,
        uint256 inputAmount,
        uint256 length
    ) internal pure returns (Input[] memory inputs) {
        inputs = new Input[](length);
        for (uint256 i; i < length; ++i) {
            inputs[i] = getInput(tokenToSwapInput, inputAmount);
        }
    }
}
