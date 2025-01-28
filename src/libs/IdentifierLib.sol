// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/**
 * @notice Library to compact 2 bytes32 identifiers into a single bytes32 identifiers.
 * This allows providing a single identifier for a pair of remote contracts.
 * Counts leading 0s to ensure addresses remains unique.
 */
library IdentifierLib {
    /**
     * @notice Count the number leading of 0s in a bytes20 element upto 6
     */
    function countLeadingZeros(
        uint160 elem
    ) internal pure returns (uint8 num) {
        if (elem < type(uint112).max) {
            return 6;
        }
        if (elem < type(uint120).max) {
            return 5;
        }
        if (elem < type(uint128).max) {
            return 4;
        }
        if (elem < type(uint136).max) {
            return 3;
        }
        if (elem < type(uint144).max) {
            return 2;
        }
        if (elem < type(uint152).max) {
            return 1;
        }
        return 0;
    }

    /**
     * @notice Computes a identifier for a route.
     * The first 15 bytes is of the original origin.
     * The last 15 bytes is of this contract.
     * @dev For the identifier to be unique it is required that app and oracle have been mined for 16 bytes addresses.
     * Otherwise there may be collisions.
     */
    function getIdentifier(address app, address oracle) internal pure returns (bytes32) {
        uint256 appZeros = countLeadingZeros(uint160(app));
        uint256 oracleZeros = countLeadingZeros(uint160(oracle));

        return bytes32(
            (appZeros << 248) // First byte is the app zeros.
                + ((uint256(uint160(app)) << 136) >> 8) // Address in 15 bytes.
                + (oracleZeros << 120) // 16'th byte is the oracle zeros.
                + ((uint256(uint160(oracle)) << 136) >> 136) // Address in 15 bytes.
        );
    }

    /**
     * @notice Compares 2 identifiers, to check if a true identifier is a subset of a larger
     * self reported identifier thus making the larger self reported identifier valid.
     * @dev Notice that this function does not generate unique id entifiers like hashing would.
     * The identifier is only unique IFF both trueIdentifier and selfReportedIdentifier are 16 bytes.
     * @param trueIdentifier A non-disputable valid identifier of a mechanism.
     * @param selfReportedIdentifier Identifier reported by trueIdentifier. May or may not be fraudulent.
     */
    function enhanceIdentifier(bytes32 trueIdentifier, bytes32 selfReportedIdentifier) internal pure returns (bytes32) {
        if (trueIdentifier == selfReportedIdentifier) return selfReportedIdentifier;

        // TODO: Auditors, should this be uint128?
        if (uint256(trueIdentifier) > type(uint160).max) return trueIdentifier;

        uint256 oracleZeros = countLeadingZeros(uint160(uint256(trueIdentifier)));

        // Check if the last 16 bytes matches. If they do, then assume that the entire identifier is valid.
        // Also check if this is a pesudo-evm address (bytes20)
        if (((uint256(trueIdentifier) << 136) >> 8) + (oracleZeros << 248) == (uint256(selfReportedIdentifier) << 128)) {
            return selfReportedIdentifier;
        }

        return trueIdentifier;
    }
}
