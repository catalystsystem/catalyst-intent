// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";

import { WrongChain } from "../interfaces/Errors.sol";
import { Output } from "../interfaces/ISettlementContract.sol";
import { OrderKey, OutputDescription } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";
import { BaseOracle } from "./BaseOracle.sol";
/**
 * @dev Oracles are also fillers
 */

contract GeneralisedIncentivesOracle is BaseOracle {
    error NotEnoughGasExecution();

    // The maximum gas used on calls is 1 million gas.
    uint256 constant MAX_GAS_ON_CALL = 1_000_000;

    constructor(address _escrow, uint32 chainId) BaseOracle(_escrow, chainId) { }

    /**
     * @notice Allows calling an external function in a non-griefing manner.
     * Source: https://github.com/catalystdao/GeneralisedIncentives/blob/38a88a746c7c18fb5d0f6aba195264fce34944d1/src/IncentivizedMessageEscrow.sol#L680
     */
    function _call(OutputDescription calldata output) internal {
        address recipient = address(uint160(uint256(output.recipient)));
        bytes memory payload = abi.encodeWithSignature(
            "outputFilled(bytes32,uint256,bytes)", output.token, output.amount, output.remoteCall
        );
        bool success;
        assembly ("memory-safe") {
            // Because Solidity always create RETURNDATACOPY for external calls, even low-level calls where no variables are assigned,
            // the contract can be attacked by a so called return bomb. This incur additional cost to the relayer they aren't paid for.
            // To protect the relayer, the call is made in inline assembly.
            success := call(MAX_GAS_ON_CALL, recipient, 0, add(payload, 0x20), mload(payload), 0, 0)
            // This is what the call would look like non-assembly.
            // recipient.call{gas: MAX_GAS_ON_CALL}(
            //      abi.encodeWithSignature("outputFilled(bytes32, uint256,bytes)", output.token, output.amount, output.remoteCall)
            // );
        }

        // External calls are allocated gas according roughly the following: min( gasleft * 63/64, gasArg ).
        // If there is no check against gasleft, then a relayer could potentially cheat by providing less gas.
        // Without a check, they only have to provide enough gas such that any further logic executees on 1/64 of gasleft
        // To ensure maximum compatibility with external tx simulation and gas estimation tools we will check a more complex
        // but more forgiving expression.
        // Before the call, there needs to be at least maxGasAck * 64/63 gas available. With that available, then
        // the call is allocated exactly min(+(maxGasAck * 64/63 * 63/64), maxGasAck) = maxGasAck.
        // If the call uses up all of the gas, then there must be maxGasAck * 64/63 - maxGasAck = maxGasAck * 1/63
        // gas left. It is sufficient to check that smaller limit rather than the larger limit.
        // Furthermore, if we only check when the call fails we don't have to read gasleft if it is not needed.
        unchecked {
            if (!success) if (gasleft() < MAX_GAS_ON_CALL * 1 / 63) revert NotEnoughGasExecution();
        }
        // Why is this better (than checking before)?
        // 1. We only have to check when the call fail. The vast majority of acks should not revert so it won't be checked.
        // 2. For the majority of applications it is going to be hold that: gasleft > rest of logic > maxGasAck * 1 / 63
        // and as such won't impact and execution/gas simuatlion/estimation libs.

        // Why is this worse?
        // 1. What if the application expected us to check that it got maxGasAck? It might assume that it gets
        // maxGasAck, when it turns out it got less it silently reverts (say by a low level call ala ours).
    }

    /**
     * @notice Verifies & Fills an order.
     * If an order has already been filled given the output & fillDeadline, then this function
     * doesn't "re"fill the order but returns early. Thus this function can also be used to verify
     * that an order was filled.
     * @dev Does not automatically submit the order (send the proof).
     * The implementation strategy (verify then fill) means that an order with repeat outputs
     * (say 1 Ether to A & 1 Ether to A) can be filled by sending 1 Ether to A ONCE.
     * !Don't make orders with repeat outputs. This is true for any oracles.
     * @param output Output to fill.
     * @param fillDeadline FillDeadline to match, is proof deadline of order.
     */
    function _fill(OutputDescription calldata output, uint32 fillDeadline) internal {
        // Check if this is the correct chain.
        _validateChain(output.chainId);

        // Get hash of output.
        bytes32 outputHash = _outputHash(output);

        // Get the proof state of the fulfillment.
        bool proofState = _provenOutput[outputHash][fillDeadline][bytes32(0)];
        // Early return if we have already seen proof.
        if (proofState) return;

        // Validate that the timestamp that is to be set, is within bounds.
        // This ensures that one cannot fill passed orders and that it is not
        // possible to lay traps (like always transferring through this contract).
        _validateTimestamp(uint32(block.timestamp), fillDeadline);

        // Load order description.
        address recipient = address(uint160(uint256(output.recipient)));
        address token = address(uint160(uint256(output.token)));
        uint256 amount = output.amount;

        // The fill status is set before the transfer.
        // This allows the above code-chunk to act as a local re-entry check.
        _provenOutput[outputHash][fillDeadline][bytes32(0)] = true;

        // Collect tokens from the user. If this fails, then the call reverts and
        // the proof is not set to true.
        // TODO: Check if token is deployed contract?
        // TODO: The disadvantage of checking is that it may invalidate a
        // TODO: ongoing order putting the collateral at risk.
        SafeTransferLib.safeTransferFrom(token, msg.sender, recipient, amount);

        // If there is an external call associated with the fill, execute it.
        if (output.remoteCall.length > 0) _call(output);
    }

    function _fill(OutputDescription[] calldata outputs, uint32[] calldata fillDeadlines) internal {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription calldata output = outputs[i];
            uint32 fillDeadline = fillDeadlines[i];
            _fill(output, fillDeadline);
        }
    }

    //--- Solver Interface ---//

    function fill(OutputDescription[] calldata outputs, uint32[] calldata fillDeadlines) external {
        _fill(outputs, fillDeadlines);
    }

    function fillAndSubmit(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillDeadlines,
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        IncentiveDescription calldata incentive
    ) external payable {
        _fill(outputs, fillDeadlines);
        _submit(outputs, fillDeadlines, destinationIdentifier, destinationAddress, incentive);
    }
}
