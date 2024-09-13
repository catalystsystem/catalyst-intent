// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { BitcoinOracle } from "./BitcoinOracle.sol";

interface ICitrea {
    function blockNumber() external view returns (uint256);
    function blockHashes(uint256) external view returns (bytes32);
}

/**
 * @dev Bitcoin oracle using the Citrea ABI.
 */
contract CitreaOracle is BitcoinOracle {

    constructor(address _escrow, address _citrea) BitcoinOracle(_escrow, _citrea) {
    }

    function _getLatestBlockHeight() override internal view returns(uint256 currentHeight) {
        return currentHeight = ICitrea(LIGHT_CLIENT).blockNumber();
    }

    function _getBlockHash(uint256 blockNum) override internal view returns(bytes32 blockHash) {
        return blockHash = ICitrea(LIGHT_CLIENT).blockHashes(blockNum);
    }
}
