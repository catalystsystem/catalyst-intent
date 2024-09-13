// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ICitrea {
    function blockNumber() external view returns (uint256);
    function blockHashes(uint256) external view returns (bytes32);
}