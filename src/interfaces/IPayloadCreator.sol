// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IPayloadCreator {
    function arePayloadsValid(
        bytes[] calldata payloads
    ) external view returns (bool);
}
