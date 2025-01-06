//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

//--- Cross-chain proof payload structure ---//
//
// Outputs Payload (beginning)
//    CONTEXT                   0       (1 byte)
//      + NUM_OUTPUTS           1       (2 bytes)
//    OUTPUTS
//      DECODE_ABLE_SECTION
//      + ORDER_ID                      M_i+2                           (32 bytes)
//      + SOLVER                        M_i+34                          (32 bytes)
//      + TIMESTAMP                     M_i+66                          (5 bytes)
//      + OUTPUT_SIZE                   M_i+71                          (2 bytes) // TODO: 3 bytes?
//      NON_DECODE_ABLE_SECTION
//      + ORDER_TYPE                    M_i+73                          (1 bytes)
//      + TOKEN                         M_i+74                          (32 bytes)
//      + AMOUNT                        M_i+106                          (32 bytes)
//      + RECIPIENT                     M_i+138                         (32 bytes)
//      + CHAIN_ID                      M_i+170                         (32 bytes)
//      + REMOTE_CALL_LENGTH            M_i+202                         (2 bytes)
//      + REMOTE_CALL                   M_i+204                         (REMOTE_CALL_LENGTH bytes)
//      + FULFILLMENT_CONTEXT_LENGTH    M_i+204+REMOTE_CALL_LENGTH      (2 bytes)
//      + FULFILLMENT_CONTEXT           M_i+206+REMOTE_CALL_LENGTH+2    (FULFILLMENT_CONTEXT_LENGTH bytes)
//
//  where M_i = N*204 + \sum^i (REMOTE_CALL_LENGTH_i + FULFILLMENT_CONTEXT_LENGTH_i)
//            = N*71 + \sum^i (OUTPUT_SIZE)
//            = M_(i-1) + 71 + \sum^i (OUTPUT_SIZE)

//--- Contexts ---//

bytes1 constant NO_FLAG = 0x00;

//--- Common Payload ---//

uint256 constant CONTEXT_POS = 0;

uint256 constant NUM_OUTPUTS_START = 1;
uint256 constant NUM_OUTPUTS_END = 3;

//--- Output Entries ---//

uint256 constant ORDER_ID_START = 2;
uint256 constant ORDER_ID_END = 34;

uint256 constant SOLVER_START = ORDER_ID_END;
uint256 constant SOLVER_END = 66;

uint256 constant TIMESTAMP_START = SOLVER_END;
uint256 constant TIMESTAMP_END = 71;

uint256 constant OUTPUT_SIZE_START = TIMESTAMP_END;
uint256 constant OUTPUT_SIZE_END = 73;
