// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "solady/src/auth/Ownable.sol";

import { IPreValidation } from "../interfaces/IPreValidation.sol";

/**
 * @notice Grouped selective allowanced solvers
 */
contract ExclusiveOrder is IPreValidation, Ownable {
    error KeyCannotHave12EmptyBytes();

    event KeysModified(bytes32 key, address initiator, bool config);

    mapping(bytes32 => mapping(address => bool)) _allowList;

    /**
     * @notice Check if initiator is in allowlist key.
     * @dev If the first 12 bytes of key is empty, then the key is used as an explicit map.
     * @param key Allowlist Lookup key. If first 12 bytes are empty, this is used as an explicit match.
     * @param initiator Caller of the initiated transaction not
     */
    function validate(bytes32 key, address initiator) external view returns (bool) {
        return (bytes12(key) == bytes12(0)) ? address(uint160(uint256(key))) == initiator : _allowList[key][initiator];
    }

    /**
     * @notice Sets an address to the allow list.
     * @dev Key cannot be set with 12 empty bytes at the beginning.
     * @param key Lookup key of the allowlist. Can be used to maintain several lists.
     * @param initiator Address to modify status of on the allow list as described by key.
     * @param config Status to set for the initiator.
     */
    function setAllowList(bytes32 key, address initiator, bool config) external onlyOwner {
        if (bytes12(key) == bytes12(0)) revert KeyCannotHave12EmptyBytes();
        _allowList[key][initiator] = config;

        emit KeysModified(key, initiator, config);
    }
}
