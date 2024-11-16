// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solady/src/utils/ReentrancyGuard.sol";

import { ICrossCatsCallback } from "../interfaces/ICrossCatsCallback.sol";
import { Input } from "../interfaces/Structs.sol";

/**
 * @title Allows a user to specify a series of calls that should be made
 * by the handler via the message field in the deposit.
 * @notice Fork of Across Multicall Contract.
 * @dev This contract makes the calls blindly. The contract will send any remaining tokens The caller should ensure that the tokens received by the handler are completely consumed.
 */
contract MulticallHandler is ICrossCatsCallback, ReentrancyGuard {

    struct Call {
        address target;
        bytes callData;
        uint256 value;
    }

    struct Instructions {
        address setApprovalsUsingInputsFor;
        //  Calls that will be attempted.
        Call[] calls;
        // Where the tokens go if any part of the call fails.
        // Leftover tokens are sent here as well if the action succeeds.
        address fallbackRecipient;
    }

    // Emitted when one of the calls fails. Note: all calls are reverted in this case.
    event CallsFailed(Call[] calls, address indexed fallbackRecipient);

    // Emitted when there are leftover tokens that are sent to the fallbackRecipient.
    event DrainedTokens(address indexed recipient, address indexed token, uint256 indexed amount);

    // Errors
    error CallReverted(uint256 index, Call[] calls);
    error NotSelf();
    error InvalidCall(uint256 index, Call[] calls);

    modifier onlySelf() {
        _requireSelf();
        _;
    }

    /**
     * @notice Main entrypoint for the handler called by the SpokePool contract.
     * @dev This will execute all calls encoded in the msg. The caller is responsible for making sure all tokens are
     * drained from this contract by the end of the series of calls. If not, they can be stolen.
     * A drainLeftoverTokens call can be included as a way to drain any remaining tokens from this contract.
     * @param message abi encoded array of Call structs, containing a target, callData, and value for each call that
     * the contract should make.
     */
    function handleV3AcrossMessage(
        address token,
        uint256,
        address,
        bytes memory message
    ) external nonReentrant {
        Instructions memory instructions = abi.decode(message, (Instructions));

        // If there is no fallback recipient, call and revert if the inner call fails.
        if (instructions.fallbackRecipient == address(0)) {
            this.attemptCalls(instructions.calls);
            return;
        }

        // Otherwise, try the call and send to the fallback recipient if any tokens are leftover.
        (bool success, ) = address(this).call(abi.encodeCall(this.attemptCalls, (instructions.calls)));
        if (!success) emit CallsFailed(instructions.calls, instructions.fallbackRecipient);

        // If there are leftover tokens, send them to the fallback recipient regardless of execution success.
        _drainRemainingTokens(token, payable(instructions.fallbackRecipient));
    }

    function outputFilled(bytes32 token, uint256 amount, bytes calldata executionData) external nonReentrant {
        Instructions memory instructions = abi.decode(executionData, (Instructions));
        // Max 1 input that matches token and amount.
        Input memory input = Input({
            token: address(uint160(uint256(token))),
            amount: amount
        });
        Input[] memory inputs = new Input[](1);
        inputs[0] = input;

        _doInstructions(instructions, inputs);
    }

    function inputsFilled(bytes32 /* orderKeyHash */, Input[] calldata inputs, bytes calldata executionData) external nonReentrant {
        Instructions memory instructions = abi.decode(executionData, (Instructions));

        _doInstructions(instructions, inputs);
    }

    function _doInstructions(Instructions memory instructions, Input[] memory inputs) internal {
        // Set approvals base on inputs if requested.
        if (instructions.setApprovalsUsingInputsFor != address(0)) _setApprovals(inputs, instructions.setApprovalsUsingInputsFor);

        // If there is no fallback recipient, call and revert if the inner call fails.
        if (instructions.fallbackRecipient == address(0)) {
            this.attemptCalls(instructions.calls);
            return;
        }

        // Otherwise, try the call and send to the fallback recipient if any tokens are leftover.
        (bool success, ) = address(this).call(abi.encodeCall(this.attemptCalls, (instructions.calls)));
        if (!success) emit CallsFailed(instructions.calls, instructions.fallbackRecipient);

        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            // If there are leftover tokens, send them to the fallback recipient regardless of execution success.
            _drainRemainingTokens(inputs[i].token, payable(instructions.fallbackRecipient));
        }
    }

    function _setApprovals(Input[] memory inputs, address to) internal {
        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            Input memory input = inputs[i];
            SafeTransferLib.safeApproveWithRetry(input.token, to, input.amount);
        }
    }

    function attemptCalls(Call[] memory calls) external onlySelf {
        uint256 length = calls.length;
        for (uint256 i = 0; i < length; ++i) {
            Call memory call = calls[i];

            // If we are calling an EOA with calldata, assume target was incorrectly specified and revert.
            if (call.callData.length > 0 && call.target.code.length == 0) {
                revert InvalidCall(i, calls);
            }

            // wake-disable-next-line reentrancy
            (bool success, ) = call.target.call{ value: call.value }(call.callData);
            if (!success) revert CallReverted(i, calls);
        }
    }

    function drainLeftoverTokens(address token, address payable destination) external onlySelf {
        _drainRemainingTokens(token, destination);
    }

    function _drainRemainingTokens(address token, address payable destination) internal {
        if (token != address(0)) {
            // ERC20 token.
            uint256 amount = SafeTransferLib.balanceOf(token, address(this));
            if (amount > 0) {
                SafeTransferLib.safeTransfer(token, destination, amount);
                emit DrainedTokens(destination, token, amount);
            }
        } else {
            // Send native token
            uint256 amount = address(this).balance;
            if (amount > 0) {
                SafeTransferLib.safeTransferETH(destination, amount);
            }
        }
    }

    function _requireSelf() internal view {
        // Must be called by this contract to ensure that this cannot be triggered without the explicit consent of the
        // depositor (for a valid relay).
        if (msg.sender != address(this)) revert NotSelf();
    }

    // Used if the caller is trying to unwrap the native token to this contract.
    receive() external payable {}
}