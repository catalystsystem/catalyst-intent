// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Input, Output } from "../../src/interfaces/ISettlementContract.sol";

import { OutputDescription } from "../../src/interfaces/Structs.sol";

import { FillerDataLib } from "../../src/libs/FillerDataLib.sol";
import { CatalystDutchOrderData } from "../../src/libs/ordertypes/CrossChainDutchOrderType.sol";
import { CatalystLimitOrderData } from "../../src/libs/ordertypes/CrossChainLimitOrderType.sol";

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
        uint32 challengeDeadline,
        uint32 proofDeadline,
        address localOracle,
        address remoteOracle
    ) internal view returns (CatalystLimitOrderData memory limitOrderData) {
        Input[] memory inputs = new Input[](1);
        inputs[0] = getInput(tokenToSwapInput, inputAmount);
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = getDescriptionOutput(
            bytes32(abi.encode(remoteOracle)), tokenToSwapOutput, outputAmount, recipient, uint32(block.chainid), hex""
        );

        limitOrderData = CatalystLimitOrderData({
            proofDeadline: proofDeadline,
            challengeDeadline: challengeDeadline,
            collateralToken: collateralToken,
            fillerCollateralAmount: fillerCollateralAmount,
            challengerCollateralAmount: challengerCollateralAmount,
            localOracle: localOracle,
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
    ) internal view returns (CatalystLimitOrderData memory limitOrderData) {
        Input[] memory inputs = getInputs(tokenToSwapInput, inputAmount, length);
        OutputDescription[] memory outputs = getDescriptionOutputs(
            bytes32(abi.encode(remoteOracle)),
            tokenToSwapOutput,
            outputAmount,
            recipient,
            uint32(block.chainid),
            hex"",
            length
        );

        limitOrderData = CatalystLimitOrderData({
            proofDeadline: proofDeadline,
            challengeDeadline: challengeDeadline,
            collateralToken: collateralToken,
            fillerCollateralAmount: fillerCollateralAmount,
            challengerCollateralAmount: challengerCollateralAmount,
            localOracle: localOracle,
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
        uint32 challengeDeadline,
        uint32 proofDeadline,
        address localOracle,
        address remoteOracle
    ) internal view returns (CatalystDutchOrderData memory dutchOrderData) {
        Input[] memory inputs = new Input[](1);
        inputs[0] = getInput(tokenToSwapInput, inputAmount);
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = getDescriptionOutput(
            bytes32(abi.encode(remoteOracle)), tokenToSwapOutput, outputAmount, recipient, uint32(block.chainid), hex""
        );

        int256[] memory inputSlopes = new int256[](1);
        int256[] memory outputSlopes = new int256[](1);

        dutchOrderData = CatalystDutchOrderData({
            verificationContext: "0x",
            verificationContract: address(0),
            challengeDeadline: challengeDeadline,
            proofDeadline: proofDeadline,
            collateralToken: collateralToken,
            fillerCollateralAmount: fillerAmount,
            challengerCollateralAmount: challengerAmount,
            localOracle: localOracle,
            slopeStartingTime: 0,
            inputSlopes: inputSlopes,
            outputSlopes: outputSlopes,
            inputs: inputs,
            outputs: outputs
        });
    }

    function getInput(address tokenToSwapInput, uint256 inputAmount) internal pure returns (Input memory input) {
        input = Input({ token: tokenToSwapInput, amount: inputAmount });
    }

    function getDescriptionOutput(
        bytes32 remoteOracle,
        address tokenToSwapOutput,
        uint256 outputAmount,
        address recipient,
        uint32 chainId,
        bytes memory remoteCall
    ) internal pure returns (OutputDescription memory output) {
        output = OutputDescription({
            token: bytes32(abi.encode(tokenToSwapOutput)),
            amount: outputAmount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: chainId,
            remoteOracle: remoteOracle,
            remoteCall: remoteCall
        });
    }

    function getDescriptionOutputs(
        bytes32 remoteOracle,
        address tokenToSwapOutput,
        uint256 outputAmount,
        address recipient,
        uint32 chainId,
        bytes memory remoteCall,
        uint256 length
    ) internal pure returns (OutputDescription[] memory outputs) {
        outputs = new OutputDescription[](length);
        for (uint256 i; i < length; ++i) {
            outputs[i] =
                getDescriptionOutput(remoteOracle, tokenToSwapOutput, outputAmount, recipient, chainId, remoteCall);
        }
    }

    function getSettlementOutput(
        bytes32 tokenToSwapOutput,
        uint256 outputAmount,
        bytes32 recipient,
        uint32 chainId
    ) internal pure returns (Output memory output) {
        output = Output({ token: tokenToSwapOutput, amount: outputAmount, recipient: recipient, chainId: chainId });
    }

    function getSettlementOutputs(
        bytes32 tokenToSwapOutput,
        uint256 outputAmount,
        bytes32 recipient,
        uint32 chainId,
        uint256 length
    ) internal pure returns (Output[] memory outputs) {
        outputs = new Output[](length);
        for (uint256 i; i < length; ++i) {
            outputs[i] = getSettlementOutput(tokenToSwapOutput, outputAmount, recipient, chainId);
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
