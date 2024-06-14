// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";

import { Output } from "../interfaces/ISettlementContract.sol";
import { OrderKey } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";
import { BaseOracle } from "./BaseOracle.sol";

/**
 * @dev Oracles are also fillers
 */
contract GeneralisedIncentivesOracle is ICrossChainReceiver, BaseOracle {
    constructor(address _escrow) BaseOracle(_escrow) { }

    /**
     * @notice Fills an order but does not automatically submit the fill for evaluation on the source chain.
     * @param output The output to fill.
     * @param fillTime The filltime to match. This is used when verifying
     * the transaction took place.
     */
    function _fill(Output calldata output, uint32 fillTime) internal {
        _validateTimestamp(uint32(block.timestamp), fillTime);

        // Check if this is the correct chain.
        // TODO: immutable chainid?
        if (uint32(block.chainid) != output.chainId) require(false, "WrongChain()"); // TODO: custom error

        // Check if this has already been filled. If it hasn't return set = false.
        bytes32 outputHash = _outputHash(output, bytes32(0)); // TODO: salt
        bool alreadyProven = _provenOutput[outputHash][fillTime][bytes32(0)];
        if (alreadyProven) return;

        address recipient = address(uint160(uint256(output.recipient)));
        address token = address(uint160(uint256(output.token)));
        uint256 amount = output.amount;
        SafeTransferLib.safeTransferFrom(token, msg.sender, recipient, amount);
        _provenOutput[outputHash][fillTime][bytes32(0)] = true;
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

    // TODO: just submit?
    // TODO: How do we standardize the submit interface?
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

    //--- Generalised Incentives ---//

    function receiveMessage(
        bytes32 sourceIdentifierbytes,
        bytes32, /* messageIdentifier */
        bytes calldata fromApplication,
        bytes calldata message
    ) external onlyEscrow returns (bytes memory acknowledgement) {
        (Output[] memory outputs, uint32[] memory fillTimes) = abi.decode(message, (Output[], uint32[]));

        // set the proof locally.
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            Output memory output = outputs[i];
            // Check if sourceIdentifierbytes
            // TODO: unify chainIdentifiers. (types)
            if (uint32(uint256(sourceIdentifierbytes)) != output.chainId) require(false, "wrongChain");
            uint32 fillTime = fillTimes[i];
            bytes32 outputHash = _outputHashM(output, bytes32(0)); // TODO: salt
            _provenOutput[outputHash][fillTime][bytes32(fromApplication)] = true;
        }

        // We don't care about the ack.
        return hex"";
    }

    function receiveAck(
        bytes32 destinationIdentifier,
        bytes32 messageIdentifier,
        bytes calldata acknowledgement
    ) external onlyEscrow {
        // We don't actually do anything on ack.
    }
}
