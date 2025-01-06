// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { ICrossCatsCallback } from "../interfaces/ICrossCatsCallback.sol";
import { Input } from "../interfaces/Structs.sol";

contract DepositIntermediary is ICrossCatsCallback {
    constructor() {}

    struct ExecutionData {
        address to;
        bytes payload;
        address fallbackTarget;
    }

    function outputFilled(bytes32 token, uint256 amount, bytes calldata executionData) external {
        ExecutionData memory execData = abi.decode(executionData, (ExecutionData));
        // Max 1 input that matches token and amount.
        Input memory input = Input({
            token: address(uint160(uint256(token))),
            amount: amount
        });
        Input[] memory inputs = new Input[](1);
        inputs[0] = input;

        _approveCallMaybeRefund(execData, inputs);
    }

    function inputsFilled(bytes32 /* orderKeyHash */, Input[] calldata inputs, bytes calldata executionData) external {
        ExecutionData memory execData = abi.decode(executionData, (ExecutionData));
        
        _approveCallMaybeRefund(execData, inputs);
    }

    function _approveCallMaybeRefund(ExecutionData memory execData, Input[] memory inputs) internal {
        // 1. Set approvals. This allows the target to collect the tokens.
        _setApprovals(inputs, execData.to);

        // 2. Call target.
        bool success = _call(execData.to, execData.payload);

        // 3. If call failed, send to fallback.
        if (!success) {
            _fallbackRefund(inputs, execData.fallbackTarget);
        }
    }

    function _setApprovals(Input[] memory inputs, address to) internal {
        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            Input memory input = inputs[i];
            SafeTransferLib.safeApproveWithRetry(input.token, to, input.amount);
        }
    }

    function _call(
        address to,
        bytes memory payload
    ) internal returns (bool success) {
        assembly ("memory-safe") {
            success := call(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, to, 0, add(payload, 0x20), mload(payload), 0, 0)
        }
    }

    function _fallbackRefund(
        Input[] memory inputs, address to
    ) internal {
        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            Input memory input = inputs[i];
            SafeTransferLib.safeTransfer(input.token, to, input.amount);
        }
    }

}