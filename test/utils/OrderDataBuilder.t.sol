// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Input } from "../../src/interfaces/ISettlementContract.sol";

import { OutputDescription } from "../../src/interfaces/Structs.sol";

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
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = getOutput(
            tokenToSwapOutput, outputAmount, recipient, uint32(block.chainid), bytes32(abi.encode(remoteOracle))
        );

        limitOrderData = LimitOrderData({
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
    ) internal view returns (LimitOrderData memory limitOrderData) {
        Input[] memory inputs = getInputs(tokenToSwapInput, inputAmount, length);
        OutputDescription[] memory outputs = getOutputs(
            tokenToSwapOutput, outputAmount, recipient, uint32(block.chainid), length, bytes32(abi.encode(remoteOracle))
        );

        limitOrderData = LimitOrderData({
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
        uint32 proofDeadline,
        uint32 challengeDeadline,
        address localOracle,
        address remoteOracle,
        bytes32 verificationContext,
        address verificationContract
    ) internal view returns (DutchOrderData memory dutchOrderData) {
        Input[] memory inputs = new Input[](1);
        inputs[0] = getInput(tokenToSwapInput, inputAmount);
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = getOutput(
            tokenToSwapOutput, outputAmount, recipient, uint32(block.chainid), bytes32(abi.encode(remoteOracle))
        );

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
            inputs: inputs,
            outputs: outputs
        });
    }

    function getInput(address tokenToSwapInput, uint256 inputAmount) internal pure returns (Input memory input) {
        input = Input({ token: tokenToSwapInput, amount: inputAmount });
    }

    // TODO: Asem place holder.
    function getOutput(
        address tokenToSwapOutput,
        uint256 outputAmount,
        address recipient,
        uint32 chainId,
        bytes32 remoteOracle
    ) internal pure returns (OutputDescription memory output) {
        output = OutputDescription({
            token: bytes32(abi.encode(tokenToSwapOutput)),
            amount: outputAmount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: chainId,
            remoteOracle: remoteOracle,
            remoteCall: hex""
        });
    }

    function getOutputs(
        address tokenToSwapOutput,
        uint256 outputAmount,
        address recipient,
        uint32 chainId,
        uint256 length,
        bytes32 remoteOracle
    ) internal pure returns (OutputDescription[] memory outputs) {
        outputs = new OutputDescription[](length);
        for (uint256 i; i < length; ++i) {
            outputs[i] = getOutput(tokenToSwapOutput, outputAmount, recipient, chainId, remoteOracle);
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
