// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "../libs/CatalystOrderType.sol";

library OutputEncodingLibrary {
    error RemoteCallOutOfRange();

    // --- Hashing Encoding --- //

    function _encodeOutput(
        bytes32 orderId,
        bytes32 solver,
        uint40 timestamp,
        bytes32 token,
        uint256 amount,
        bytes32 recipient,
        bytes memory remoteCall
    ) internal pure returns (bytes memory encodedOutput) {
        // Check that the remoteCall does not exceed type(uint16).max
        if (remoteCall.length > type(uint16).max) revert RemoteCallOutOfRange();

        return encodedOutput = abi.encodePacked(
            orderId,
            solver,
            timestamp,
            token,
            amount,
            recipient,
            uint16(remoteCall.length), // To protect against data collisions
            remoteCall
        );
    }

    function _encodeOutputDescription(
        bytes32 orderId,
        bytes32 solver,
        uint40 timestamp,
        OutputDescription memory outputDescription
    ) internal pure returns (bytes memory encodedOutput) {
        return encodedOutput = _encodeOutput(
            orderId,
            solver,
            timestamp,
            outputDescription.token,
            outputDescription.amount,
            outputDescription.recipient,
            outputDescription.remoteCall
        );
    }
}
