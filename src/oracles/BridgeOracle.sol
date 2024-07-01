// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";

import { WrongChain } from "../interfaces/Errors.sol";
import { Output } from "../interfaces/ISettlementContract.sol";
import { OrderKey } from "../interfaces/Structs.sol";
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
     * doesn't refill the order but returns early. Thus this function can also be used to verify
     * that an order was filled.
     * @dev Does not automatically submit the order (send the proof).
     * The implementation strategy (verify then fill) means that an order with repeat outputs
     * (say 1 Ether to A & 1 Ether to A) can be filled by sending 1 Ether to A ONCE.
     * Don't make orders with repeat outputs.
     * @param output The output to fill.
     * @param fillTime The filltime to match. This is used when verifying
     * the transaction took place.
     */
    function _fill(Output calldata output, uint32 fillTime) internal {
        // Check if this is the correct chain.
        // TODO: immutable chainid?
        if (uint32(block.chainid) != output.chainId) revert WrongChain();

        // Check if this has already been filled. If it hasn't return set = false.
        bytes32 outputHash = _outputHash(output, bytes32(0)); // TODO: salt

        // Get the proof state of the fulfillment.
        bool proofState = _provenOutput[outputHash][fillTime][bytes32(0)];
        if (proofState) return;
        // If the order hasn't already been filled,
        _validateTimestamp(uint32(block.timestamp), fillTime);

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

    function _fill(Output[] calldata outputs, uint32[] calldata fillTimes) internal {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            Output calldata output = outputs[i];
            uint32 fillTime = fillTimes[i];
            _fill(output, fillTime);
        }
    }

    //--- Solver Interface ---//

    function fill(Output[] calldata outputs, uint32[] calldata fillTimes) external {
        _fill(outputs, fillTimes);
    }

    function fillAndSubmit(
        Output[] calldata outputs,
        uint32[] calldata fillTimes,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable {
        _fill(outputs, fillTimes);
        _submit(outputs, fillTimes, destinationIdentifier, destinationAddress, incentive, deadline);
    }
}
