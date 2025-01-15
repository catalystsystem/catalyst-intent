// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/**
 * @notice Library to compact 2 bytes32 identifiers into a single bytes32 identifiers.
 * This allows providing a single identifier for a pair of remote contracts.
 */
library IdentifierLib {
    /**
     * @notice Computes a identifier for a route.
     * The first 16 bytes is of the original origin.
     * The last 16 bytes is of this contract.
     * @dev For the identifier to be unique it is required that app and oracle have been mined for 16 bytes addresses. 
     * Otherwise there may be collisions.
     */
    function getIdentifier(address app, address oracle) internal pure returns (bytes32) {
        return bytes32(
            ( uint256(uint160(app)) << 128 )
            + ( (uint256(uint160(oracle)) << 128) >> 128 )
        );
    }

    /**
     * @notice Compares 2 identifiers, to check if a true identifier is a subset of a larger
     * self reported identifier thus making the larger self reported indentifier valid.
     * @dev Notice that this function does not generate unique id entifiers like hashing would.
     * The identifier is only unique IFF both trueIdentifier and selfReportedIdentifier are 16 bytes.
     * @param trueIdentifier A non-disputable valid identifier of a mechanism.
     * @param selfReportedIdentifier Identifier reported by trueIdentifier. May or may not be fradulent.
     */
    function enhanceIdentifier(bytes32 trueIdentifier, bytes32 selfReportedIdentifier) internal pure returns (bytes32) {
        if (trueIdentifier == selfReportedIdentifier) return selfReportedIdentifier;

        // Check if the last 16 bytes matches. If they do, then assume that assume that the entire identifier is valid.
        // Also check if this is a pesudo-evm address (bytes20)
        if (uint256(trueIdentifier) < uint256(type(uint160).max) && uint128(uint256(trueIdentifier)) == uint128(uint256(selfReportedIdentifier))) return selfReportedIdentifier;
        return trueIdentifier;
    }
}