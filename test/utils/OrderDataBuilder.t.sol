// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Input, Output } from "../../src/interfaces/ISettlementContract.sol";
import { LimitOrderData } from "../../src/libs/CrossChainLimitOrderType.sol";

library OrderDataBuilder {
    function getLimitOrder(
        address tokenToSwapInput,
        address tokenToSwapOutput,
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient,
        uint256 fillerAmount,
        uint256 challengerAmount,
        address localOracle,
        address remoteOracle
    ) internal pure returns (LimitOrderData memory limitOrderData) {
        Input memory input = Input({ token: tokenToSwapInput, amount: inputAmount });
        Output memory output = Output({
            token: bytes32(abi.encode(tokenToSwapOutput)),
            amount: outputAmount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(0)
        });

        limitOrderData = LimitOrderData({
            proofDeadline: 0,
            collateralToken: tokenToSwapInput,
            fillerCollateralAmount: fillerAmount,
            challengerCollateralAmount: challengerAmount,
            localOracle: localOracle,
            remoteOracle: bytes32(abi.encode(remoteOracle)),
            input: input,
            output: output
        });
    }

    //TODO: We might extend with other rectors
}
