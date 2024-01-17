// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

struct OrderDescription {
    bytes32 destinationChain;
    bytes destinationAsset; // bytes65
    bytes32 sourceChain;
    address sourceAsset;
    uint256 minBond;
    uint64 timeout;
    address sourceEvaluationContract;
    bytes32 destinationEvaluationContract;
    bytes evaluationContext;
}

struct OrderContext {
    address claimer;
    uint256 sourceAssetsClaimed;
    address sourceAsset;
}

struct Signature {
    bytes32 r;
    bytes32 s;
    uint8 v;
}