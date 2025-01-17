// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { WrongChain, WrongRemoteOracle } from "../../interfaces/Errors.sol";
import { OutputEncodingLib } from "../../libs/OutputEncodingLib.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IPayloadCreator } from "../../interfaces/IPayloadCreator.sol";

/** @notice Base  */
abstract contract BaseFiller is IPayloadCreator {

    event OutputProven(uint32 fillDeadline, bytes32 outputHash);

    uint32 public immutable CHAIN_ID = uint32(block.chainid);
    bytes16 immutable ADDRESS_THIS = bytes16(uint128(uint160(address(this)))) << 8;

    //-- Helpers --//

    /**
     * @notice Validate that expected chain (@param chainId) matches this chain's chainId (block.chainId)
     * @dev We use the chain's canonical id rather than the messaging protocol id for clarity.
     */
    function _validateChain(
        uint256 chainId
    ) internal view {
        if (block.chainid != chainId) revert WrongChain(block.chainid, uint256(chainId));
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
        bytes16 fillerIdentifier = bytes16(remoteOracleIdentifier) << 8;
        if (ADDRESS_THIS != fillerIdentifier) revert WrongRemoteOracle(ADDRESS_THIS, fillerIdentifier);
    }
}
