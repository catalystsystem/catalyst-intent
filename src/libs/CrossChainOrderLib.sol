// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

bytes constant CROSS_CHAIN_ORDER_TYPE_STUB = abi.encodePacked(
    "CrossChainOrder(",
    "address settlerContract,",
    "address swapper,",
    "uint256 nonce,",
    "uint32 originChainId,",
    "uint32 initiateDeadline,",
    "uint32 fillDeadline,"
);

bytes constant INPUT_TYPE_STUB = abi.encodePacked("Input(", "address token,", "uint256 amount", ")");

bytes constant OUTPUT_TYPE_STUB =
    abi.encodePacked("Output(", "bytes32 token,", "uint256 amount,", "bytes32 recipient,", "uint32 chainId,", ")");
