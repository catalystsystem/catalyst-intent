// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ICrossCatsCallback } from "../../src/interfaces/ICrossCatsCallback.sol";
import { InputDescription } from "../../src/reactors/CatalystOrderType.sol";

contract MockCallbackExecutor is ICrossCatsCallback {
    event InputsFilled(bytes32 orderKeyHash, bytes executionData);

    function outputFilled(bytes32 token, uint256 amount, bytes calldata executionData) external override { }

    function inputsFilled(bytes32 orderKeyHash, InputDescription[] calldata /* inputs */, bytes calldata executionData) external override {
        emit InputsFilled(orderKeyHash, executionData);
    }
}
