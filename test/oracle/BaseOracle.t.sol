// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.22;

import { BaseOracle } from "src/oracles/BaseOracle.sol";

import "forge-std/Test.sol";

contract MockBaseOracle is BaseOracle {
    function setAttestation(uint256 remoteChainId, bytes32 senderIdentifier, bytes32 application, bytes32 dataHash) external {
        _attestations[remoteChainId][senderIdentifier][application][dataHash] = true;
    }
}

contract TestBaseOracle is Test {
    MockBaseOracle baseOracle;

    function setUp() external {
        baseOracle = new MockBaseOracle();
    }

    function test_is_proven(uint256 remoteChainId, bytes32 application, bytes32 remoteOracle, bytes32 dataHash) external {
        bool statusBefore = baseOracle.isProven(remoteChainId, remoteOracle, application, dataHash);
        assertEq(statusBefore, false);

        baseOracle.setAttestation(remoteChainId, remoteOracle, application, dataHash);

        bool statusAfter = baseOracle.isProven(remoteChainId, remoteOracle, application, dataHash);
        assertEq(statusAfter, true);
    }

    function test_fuzz_efficientRequireProven(
        bytes calldata proofSeries
    ) external {
        vm.assume(proofSeries.length > 0);
        uint256 lengthOfProofSeriesIn32Chunks = proofSeries.length / (32 * 4);
        lengthOfProofSeriesIn32Chunks *= (32 * 4);
        if (lengthOfProofSeriesIn32Chunks != proofSeries.length) {
            vm.expectRevert(abi.encodeWithSignature("NotDivisible(uint256,uint256)", proofSeries.length, 32 * 4));
        } else {
            uint256 remoteChainId = uint256(bytes32(proofSeries[0:32]));
            bytes32 remoteOracle = bytes32(proofSeries[32:64]);
            bytes32 application = bytes32(proofSeries[64:96]);
            bytes32 dataHash = bytes32(proofSeries[96:128]);
            vm.expectRevert(abi.encodeWithSignature("NotProven(uint256,bytes32,bytes32,bytes32)", remoteChainId, remoteOracle, application, dataHash));
        }
        baseOracle.efficientRequireProven(proofSeries);
    }
}
