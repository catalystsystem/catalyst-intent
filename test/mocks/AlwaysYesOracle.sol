// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IOracle } from "../../src/interfaces/IOracle.sol";

contract AlwaysYesOracle is IOracle {
    
    function isProven(bytes32 remoteOracle, bytes32 remoteChainId, bytes32 dataHash) external pure returns (bool) {
        return true;
    }

    function isProven(bytes32[] calldata remoteOracles, bytes32[] calldata remoteChainIds, bytes32[] calldata dataHashes) external pure returns (bool){
        return true;
    }

    function efficientRequireProven(bytes calldata proofSeries) external pure {}
}
