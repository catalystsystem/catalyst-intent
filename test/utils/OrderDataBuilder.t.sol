// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Input, Output } from "../../src/interfaces/ISettlementContract.sol";

import { DutchOrderData } from "../../src/libs/CrossChainDutchOrderType.sol";
import { LimitOrderData } from "../../src/libs/CrossChainLimitOrderType.sol";

library OrderDataBuilder {
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
    ) internal pure returns (LimitOrderData memory limitOrderData) {
        Input[] memory inputs = new Input[](1);
        inputs[0] = getInput(tokenToSwapInput, inputAmount);
        Output[] memory outputs = new Output[](1);
        outputs[0] = getOutput(tokenToSwapOutput, outputAmount, recipient, 0);

        limitOrderData = LimitOrderData({
            proofDeadline: proofDeadline,
            challengeDeadline: challengeDeadline,
            collateralToken: collateralToken,
            fillerCollateralAmount: fillerCollateralAmount,
            challengerCollateralAmount: challengerCollateralAmount,
            localOracle: localOracle,
            remoteOracle: bytes32(abi.encode(remoteOracle)),
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
        address remoteOracle
    ) internal pure returns (DutchOrderData memory dutchOrderData) {
        Input memory input = getInput(tokenToSwapInput, inputAmount);
        Output memory output = getOutput(tokenToSwapOutput, outputAmount, recipient, 0);
        dutchOrderData = DutchOrderData({
            proofDeadline: proofDeadline,
            challengeDeadline: challengeDeadline,
            collateralToken: collateralToken,
            fillerCollateralAmount: fillerAmount,
            challengerCollateralAmount: challengerAmount,
            localOracle: localOracle,
            slopeStartingTime: 0,
            inputSlope: 0,
            outputSlope: 0,
            remoteOracle: bytes32(abi.encode(remoteOracle)),
            input: input,
            output: output
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
}
