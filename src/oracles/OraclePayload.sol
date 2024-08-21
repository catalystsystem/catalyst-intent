//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Cross-chain proof payload structure ***********************************************************************************************
//
// Outputs Payload (beginning)
//    CONTEXT                   0       (1 byte)
//      + NUM_OUTPUTS           1       (2 bytes)
//    OUTPUTS
//      + TOKEN                 M_i+3       (32 bytes)
//      + AMOUNT                M_i+35      (32 bytes)
//      + RECIPIENT             M_i+67      (32 bytes)
//      + CHAIN_ID              M_i+99      (4 bytes)
//      + FILLTIME              M_i+103     (4 bytes)
//      + REMOTE_CALL_LENGTH    M_i+107     (2 bytes)
//      + REMOTE_CALL           M_i+109     (REMOTE_CALL_LENGTH bytes)
//
//  where M_i = N*109 + \sum REMOTE_CALL_LENGTH_i
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

uint256 constant OUTPUT_LENGTH = REMOTE_CALL_START - OUTPUT_TOKEN_START;

uint256 constant OUTPUT_TOKEN_START = 3;
uint256 constant OUTPUT_TOKEN_END = 35;

uint256 constant OUTPUT_AMOUNT_START = 35;
uint256 constant OUTPUT_AMOUNT_END = 67;

uint256 constant OUTPUT_RECIPIENT_START = 67;
uint256 constant OUTPUT_RECIPIENT_END = 99;

uint256 constant OUTPUT_CHAIN_ID_START = 99;
uint256 constant OUTPUT_CHAIN_ID_END = 103;

uint256 constant OUTPUT_FILLTIME_START = 103;
uint256 constant OUTPUT_FILLTIME_END = 107;

uint256 constant REMOTE_CALL_LENGTH_START = 107;
uint256 constant REMOTE_CALL_LENGTH_END = 109;

uint256 constant REMOTE_CALL_START = 109;

// FLAG1 - 0x01 - Execute Proof

uint256 constant FLAG1_START = 168;
