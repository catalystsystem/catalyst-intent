
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.22;

import { BaseOracle } from  "src/oracles/BaseOracle.sol";

import "forge-std/Test.sol";


contract MockBaseOracle is BaseOracle {
    function setAttestation(uint256 remoteChainId, bytes32 senderIdentifier, bytes32 dataHash) external {
        _attestations[remoteChainId][senderIdentifier][dataHash] = true;
    }
}

contract TestBaseOracle is Test {
    MockBaseOracle baseOracle;

    function setUp() external {
        baseOracle = new MockBaseOracle();
    }

    function test_is_proven(uint256 remoteChainId, bytes32 remoteOracle, bytes32 dataHash) external {
        bool statusBefore = baseOracle.isProven(remoteChainId, remoteOracle, dataHash);
        assertEq(statusBefore, false);

        baseOracle.setAttestation(remoteChainId, remoteOracle, dataHash);

        bool statusAfter = baseOracle.isProven(remoteChainId, remoteOracle, dataHash);
        assertEq(statusAfter, true);
    }

    function test_is_provens(bytes32[3][] calldata proofs) external {
        vm.assume(proofs.length > 0);
        uint256[] memory remoteChainIds = new uint256[](proofs.length);
        bytes32[] memory remoteOracles = new bytes32[](proofs.length);
        bytes32[] memory dataHashes = new bytes32[](proofs.length);
        for (uint256 i; i < proofs.length; ++i) {
            remoteChainIds[i] = uint256(proofs[i][0]);
            remoteOracles[i] = proofs[i][1];
            dataHashes[i] = proofs[i][2];
        }

        bool statusBefore = baseOracle.isProven(remoteChainIds, remoteOracles, dataHashes);
        assertEq(statusBefore, false);

        for (uint256 i; i < proofs.length; ++i) {
            baseOracle.setAttestation(remoteChainIds[i], remoteOracles[i], dataHashes[i]);
        }

        bool statusAfter = baseOracle.isProven(remoteChainIds, remoteOracles, dataHashes);
        assertEq(statusAfter, true);
    }

    function test_fuzz_efficientRequireProven(bytes calldata proofSeries) external {
        vm.assume(proofSeries.length > 0);
        uint256 lengthOfProofSeriesIn32Chunks = proofSeries.length / (32 * 3);
        lengthOfProofSeriesIn32Chunks *= (32 * 3);
        if (lengthOfProofSeriesIn32Chunks != proofSeries.length) {
            vm.expectRevert(abi.encodeWithSignature("NotDivisible(uint256,uint256)", proofSeries.length, 32 * 3));
        } else {
            uint256 remoteChainId = uint256(bytes32(proofSeries[0:32]));
            bytes32 remoteOracle  = bytes32(proofSeries[32:64]);
            bytes32 dataHash  = bytes32(proofSeries[64:96]);
            vm.expectRevert(abi.encodeWithSignature("NotProven(uint256,bytes32,bytes32)", remoteChainId, remoteOracle, dataHash));
        }
        baseOracle.efficientRequireProven(proofSeries);
    }
}
