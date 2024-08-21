// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICrossCatsCallback {
    function outputFilled(
        bytes32 token,
        uint256 amount,
        bytes calldata executionData
    ) external;

    function orderPurchaseCallback(
        bytes32 orderKeyHash,
        bytes calldata executionData
    ) external;
}
