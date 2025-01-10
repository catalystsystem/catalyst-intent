// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { WrongChain, WrongRemoteOracle } from "../../interfaces/Errors.sol";
import { OutputEncodingLibrary } from "../OutputEncodingLibrary.sol";
import { IOracle } from "../../interfaces/IOracle.sol";


abstract contract BaseFiller {

    event OutputProven(uint32 fillDeadline, bytes32 outputHash);

    uint32 public immutable CHAIN_ID = uint32(block.chainid);
    bytes16 immutable ADDRESS_THIS = bytes16(uint128(uint160(address(this))));

    //-- Helpers --//

    /**
     * @notice Validate that expected chain (@param chainId) matches this chain's chainId (block.chainId)
     * @dev We use the chain's canonical id rather than the messaging protocol id for clarity.
     */
    function _validateChain(
        bytes32 chainId
    ) internal view {
        if (block.chainid != uint256(chainId)) revert WrongChain(block.chainid, uint256(chainId));
    }

    /**
     * @notice Validate that the remote oracle address is this oracle.
     * @dev For some oracles, it might be required that you "cheat" and change the encoding here.
     * Don't worry (or do worry) because the other side loads the payload as bytes32(bytes).
     */
    function _IAmRemoteOracle(
        bytes32 remoteOracleIdentifier
    ) internal view virtual {
        // Load the first 16 bytes.
        bytes16 fillerIdentifier = bytes16(remoteOracleIdentifier);
        if (ADDRESS_THIS != fillerIdentifier) revert WrongRemoteOracle(ADDRESS_THIS, fillerIdentifier);
    }

    function _getOracleAddress(
        bytes32 remoteOracleIdentifier
    ) internal view virtual returns (address) {
        // Load the last 16 bytes.
        return address(uint160(uint128(uint256(remoteOracleIdentifier))));
    }
}
