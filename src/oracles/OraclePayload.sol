//SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Cross-chain proof payload structure ***********************************************************************************************
//
// Outputs Payload (beginning)
//    CONTEXT               0       (1 byte)
//      + NUM_OUTPUTS       1       (2 bytes)
//    OUTPUTS
//      + TOKEN             N*132+3     (32 bytes)
//      + AMOUNT            N*132+35    (32 bytes)
//      + RECIPIENT         N*133+67    (32 bytes)
//      + CHAIN_ID          N*132+99    (32 bytes) // TODO: length?
//      + FILLTIME          N*132+131   (4 bytes)
//
// Context-depending Payload
//    FLAG1 - 0x01 - Execute Proof // TODO:
//       + ORDER_KEY        N*132+136   (TODO bytes)

// Contexts *********************************************************************************************************************

bytes1 constant NO_FLAG = 0x00;
bytes1 constant EXECUTE_PROOFS = 0x01;

// Common Payload ***************************************************************************************************************

uint256 constant CONTEXT_POS = 0;

uint256 constant NUM_OUTPUTS_START = 1;
uint256 constant NUM_OUTPUTS_END = 3;

// Output Entries ***************************************************************************************************************

uint256 constant OUTPUT_LENGTH = 40;

uint256 constant OUTPUT_HASH_START = 3;
uint256 constant OUTPUT_HASH_END = 35;

uint256 constant OUTPUT_CHAIN_ID_START = 35;
uint256 constant OUTPUT_CHAIN_ID_END = 39;

uint256 constant OUTPUT_FILLTIME_START = 39;
uint256 constant OUTPUT_FILLTIME_END = 43;

// FLAG1 - 0x01 - Execute Proof

uint256 constant FLAG1_START = 44;
