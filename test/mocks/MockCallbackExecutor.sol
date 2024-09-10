// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ICrossCatsCallback } from "../../src/interfaces/ICrossCatsCallback.sol";

contract MockCallbackExecutor is ICrossCatsCallback {
    event OutputFilled(bytes32 token, uint256 amount, bytes executionData);
    event InputsFilled(bytes32 orderKeyHash, bytes executionData);

    function outputFilled(bytes32 token, uint256 amount, bytes calldata executionData) external override {
        emit OutputFilled(token, amount, executionData);
    }

    function inputsFilled(bytes32 orderKeyHash, bytes calldata executionData) external override {
        emit InputsFilled(orderKeyHash, executionData);
    }
}
