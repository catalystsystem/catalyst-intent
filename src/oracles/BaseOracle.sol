// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { IOracle } from "../interfaces/IOracle.sol";
import { Output } from "../interfaces/ISettlementContract.sol";
import { OrderKey } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";

/**
 * @dev Oracles are also fillers
 */
abstract contract BaseOracle is IMessageEscrowStructs, IOracle {
    uint256 constant MAX_FUTURE_FILL_TIME = 7 days;

    mapping(bytes32 outputHash => mapping(uint32 fillTime => mapping(bytes32 oracle => bool proven))) internal
        _provenOutput;

    IIncentivizedMessageEscrow public immutable escrow;

    error NotApprovedEscrow();

    constructor(address _escrow) {
        // Solution 1: Set the escrow.
        escrow = IIncentivizedMessageEscrow(_escrow);
    }

    modifier onlyEscrow() {
        if (msg.sender != address(escrow)) revert NotApprovedEscrow();
        _;
    }

    function isProven(Output calldata output, uint32 fillTime, bytes32 oracle) external view returns (bool proven) {
        bytes32 outputHash = _outputHash(output, bytes32(0));
        return _provenOutput[outputHash][fillTime][oracle];
    }

    function isProven(Output[] calldata outputs, uint32 fillTime, bytes32 oracle) public view returns (bool proven) {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            bytes32 outputHash = _outputHash(outputs[i], bytes32(0)); // TODO: output salt potentiall also by adding the orderKeyHash to it.
            if (!_provenOutput[outputHash][fillTime][oracle]) {
                return proven = false;
            }
        }
        return proven = true;
    }

    /**
     * TODO: define an output salt which is some value (time + nonce?) that allows us to
     * discriminate between different outputs in time & space.
     */
    function _outputHash(Output calldata output, bytes32 outputSalt) internal pure returns (bytes32) {
        return keccak256(bytes.concat(abi.encode(output), outputSalt)); // TODO: Efficiency? // TODO: hash with orderKeyHash for collision?
    }

    function _outputHashM(Output memory output, bytes32 outputSalt) internal pure returns (bytes32) {
        return keccak256(bytes.concat(abi.encode(output), outputSalt)); // TODO: Efficiency? // TODO: hash with orderKeyHash for collision?
    }

    function _validateTimestamp(uint32 timestamp, uint32 fillTime) internal pure {
        // FillTime may not be in the past.
        if (fillTime < timestamp) require(false, "FillTimeInPast()"); // TODO: custom error.
        // Check that fillTime isn't far in the future.
        // The idea is to protect users against random transfers through this contract.
        if (fillTime > timestamp + MAX_FUTURE_FILL_TIME) require(false, "FillTimeFarInFuture()");
    }

    //--- Sending Proofs ---//

    // TODO: figure out what the best best interface for this function is
    function _submit(
        Output[] calldata outputs,
        uint32[] calldata filledTimes,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) internal {
        // TODO: Figure out a better idea than abi.encode
        bytes memory message = abi.encode(outputs, filledTimes);
        // Deadline is set to 0.
        escrow.submitMessage(destinationIdentifier, destinationAddress, message, incentive, deadline);
    }
}
