// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

struct BitcoinChain {
    bytes blockHeader;
    address escrow;
    bool isTestNet;
    IterBlock iterBlock;
    Prism prism;
    TX tx;
}
// TX tx;

struct Prism {
    bytes32 blockHash;
    uint120 blockHeight;
    uint120 blockTime;
    bytes32 expectedTarget;
}

struct TX {
    bytes32 id;
    uint256 index;
    string merkleProof;
    uint256 outputIndex;
    bytes rawTx;
    uint256 satsAmount;
    bytes32 utxoType;
}

struct IterBlock {
    bytes blockHeaders;
    uint256 blockHeight;
}
