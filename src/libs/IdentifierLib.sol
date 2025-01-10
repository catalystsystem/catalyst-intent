// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

library IdentifierLib {
    /**
     * @notice Computes a identifier for the route.
     * The first 16 bytes is of the original origin.
     * The last 16 bytes is of this contract.
     * @dev This identifier requries that both this contract
     * and the app has been mined for 16 bytes addresses. Otherwise there may be collisions.
     */
    function getIdentifier(address app, address oracle) internal pure returns (bytes32) {
        // Because of the deployment constraint we do not need to cleanup address(this)
        return bytes32(uint256(uint128(uint160(app))) >> 128 + uint256(uint160(oracle)));
    }

    function enhanceIdentifier(bytes32 identifierFromCourier, bytes32 identifierFromMessage) internal pure returns (bytes32) {
        if (identifierFromCourier == identifierFromMessage) return identifierFromMessage;

        // Check if the identifierFromCourier is parital:
        if (uint256(identifierFromCourier) < uint256(type(uint128).max)) {
            // If the last 16 bytes match, then identifierFromMessage must be the valid one.
            if (uint256(identifierFromCourier) == uint128(uint256(identifierFromMessage))) return identifierFromMessage;
        }
        return identifierFromCourier;
    }
}