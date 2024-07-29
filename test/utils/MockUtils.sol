// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { MockERC20 } from "../mocks/MockERC20.sol";

library MockUtils {
    function test() public pure { }

    function getCurrentBalances(
        address tokenToSwap,
        address swapper,
        address reactorAddress
    ) internal view returns (uint256 swapperInputBalance, uint256 reactorInputBalance) {
        swapperInputBalance = MockERC20(tokenToSwap).balanceOf(swapper);
        reactorInputBalance = MockERC20(tokenToSwap).balanceOf(reactorAddress);
    }
}
