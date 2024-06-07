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
