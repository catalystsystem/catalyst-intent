// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

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
    constructor(address _escrow) BaseOracle(_escrow) { }

    /**
     * @notice Verifies & Fills an order.
     * If an order has already been filled given the output & fillTime, then this function
     * doesn't "re"fill the order but returns early. Thus this function can also be used to verify
     * that an order was filled.
     * @dev Does not automatically submit the order (send the proof).
     * The implementation strategy (verify then fill) means that an order with repeat outputs
     * (say 1 Ether to A & 1 Ether to A) can be filled by sending 1 Ether to A ONCE.
     * !Don't make orders with repeat outputs. This is true for any oracles.
     * @param output Output to fill.
     * @param fillTime Filltime to match, is proof deadline of order.
     */
    function _fill(OutputDescription calldata output, uint32 fillTime) internal {
        // Check if this is the correct chain.
        // TODO: fix chainid to be based on the messaging protocol being used
        if (uint32(block.chainid) != output.chainId) revert WrongChain();

        // Get hash of output.
        bytes32 outputHash = _outputHash(output);

        // Get the proof state of the fulfillment.
        bool proofState = _provenOutput[outputHash][fillTime][bytes32(0)];
        // Early return if we have already seen proof.
        if (proofState) return;

        // Validate that the timestamp that is to be set, is within bounds.
        // This ensures that one cannot fill passed orders and that it is not
        // possible to lay traps (like always transferring through this contract).
        _validateTimestamp(uint32(block.timestamp), fillTime);

        // Load order description.
        address recipient = address(uint160(uint256(output.recipient)));
        address token = address(uint160(uint256(output.token)));
        uint256 amount = output.amount;

        // The fill status is set before the transfer.
        // This allows the above code-chunk to act as a local re-entry check.
        _provenOutput[outputHash][fillTime][bytes32(0)] = true;

        // Collect tokens from the user. If this fails, then the call reverts and
        // the proof is not set to true.
        // TODO: Check if token is deployed contract?
        // TODO: The disadvantage of checking is that it may invalidate a
        // TODO: ongoing order putting the collateral at risk.
        SafeTransferLib.safeTransferFrom(token, msg.sender, recipient, amount);
    }

    function _fill(OutputDescription[] calldata outputs, uint32[] calldata fillTimes) internal {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription calldata output = outputs[i];
            uint32 fillTime = fillTimes[i];
            _fill(output, fillTime);
        }
    }

    //--- Solver Interface ---//

    function fill(OutputDescription[] calldata outputs, uint32[] calldata fillTimes) external {
        _fill(outputs, fillTimes);
    }

    function fillAndSubmit(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillTimes,
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        IncentiveDescription calldata incentive
    ) external payable {
        _fill(outputs, fillTimes);
        _submit(outputs, fillTimes, destinationIdentifier, destinationAddress, incentive);
    }
}
