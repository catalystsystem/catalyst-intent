// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { BaseFiller } from "./BaseFiller.sol";
import { OutputEncodingLibrary } from  "../OutputEncodingLibrary.sol";
import { IdentifierLib } from "../../libs/IdentifierLib.sol";

abstract contract SolverTimestampBaseFiller is BaseFiller {
    // TODO: Optimise stack?
    struct FilledOutput {
        bytes32 solver;
        uint40 timestamp;
    }

    mapping(bytes32 orderId => mapping(bytes32 outputHash => FilledOutput)) _filledOutput;

    // --- Oracles --- //

    function _isValidPayload(address oracle, bytes calldata payload) view internal returns(bool) {
        bytes32 remoteOracleIdentifier = IdentifierLib.getIdentifier(address(this), oracle);
        uint256 chainId = block.chainid;
        bytes32 outputHash = OutputEncodingLibrary.payloadToOutputHash(remoteOracleIdentifier, chainId, OutputEncodingLibrary.selectRemainingPayload(payload));

        bytes32 orderId = OutputEncodingLibrary.decodePayloadOrderId(payload);
        FilledOutput storage filledOutput = _filledOutput[orderId][outputHash];

        bytes32 filledSolver = filledOutput.solver;
        uint40 filledTimestamp = filledOutput.timestamp;
        if (filledSolver == bytes32(0)) return false;

        bytes32 payloadSolver = OutputEncodingLibrary.decodePayloadSolver(payload);
        uint40 payloadTimestamp = OutputEncodingLibrary.decodePayloadTimestamp(payload);

        if (filledSolver != payloadSolver) return false;
        if (filledTimestamp != payloadTimestamp) return false;

        return true;
    }

    function areValidPayloads(bytes[] calldata payloads) view external returns(bool) {
        address sender = msg.sender;
        uint256 numPayloads = payloads.length;
        for (uint256 i; i < numPayloads; ++i) {
            if (!_isValidPayload(sender, payloads[i])) return false;
        }
        return true;
    }
}