// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "../CatalystOrderType.sol";
import { BaseFiller } from "./BaseFiller.sol";
import { OutputEncodingLib } from  "../../libs/OutputEncodingLib.sol";
import { IdentifierLib } from "../../libs/IdentifierLib.sol";

abstract contract SolverTimestampBaseFiller is BaseFiller {
    event OutputFilled(bytes32 orderId, bytes32 solver, uint32 timestamp, OutputDescription output);

    // TODO: Optimise stack?
    struct FilledOutput {
        bytes32 solver;
        uint32 timestamp;
    }

    mapping(bytes32 orderId => mapping(bytes32 outputHash => FilledOutput)) _filledOutput;

    // --- Oracles --- //

    function _isValidPayload(address oracle, bytes calldata payload) view virtual internal returns(bool) {
        bytes32 remoteOracleIdentifier = IdentifierLib.getIdentifier(address(this), oracle);
        uint256 chainId = block.chainid;
        bytes32 outputHash = OutputEncodingLib.payloadToOutputHash(remoteOracleIdentifier, chainId, OutputEncodingLib.selectRemainingPayload(payload));

        bytes32 orderId = OutputEncodingLib.decodePayloadOrderId(payload);
        FilledOutput storage filledOutput = _filledOutput[orderId][outputHash];

        bytes32 filledSolver = filledOutput.solver;
        uint32 filledTimestamp = filledOutput.timestamp;
        if (filledSolver == bytes32(0)) return false;

        bytes32 payloadSolver = OutputEncodingLib.decodePayloadSolver(payload);
        uint32 payloadTimestamp = OutputEncodingLib.decodePayloadTimestamp(payload);

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