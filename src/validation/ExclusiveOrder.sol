// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "solady/src/auth/Ownable.sol";

import { IPreValidation } from "../interfaces/IPreValidation.sol";

/**
 * @notice Selectively allow solvers.
 * This validation contract supports setting single approved solver.
 * Customizing an allowlist can only be done by the owner of the contract.
 * The owner is always allowed.
 */
contract ExclusiveOrder is IPreValidation, Ownable {
    error KeyCannotHave12EmptyBytes();

    event KeysModified(bytes32 key, address initiator, bool config);

    mapping(bytes32 => mapping(address => bool)) _allowList;

    constructor(address owner) {
        _initializeOwner(owner);
    }

    /**
     * @notice Check if initiator is in allowlist key.
     * @dev If the first 12 bytes of key is empty, then the key is used as an explicit map.
     * @param key Allowlist Lookup key. If first 12 bytes are empty, this is used as an explicit match.
     * @param initiator Caller of the initiated transaction not
     */
    function validate(bytes32 key, address initiator) external view returns (bool) {
        return (bytes12(key) == bytes12(0))
            ? address(uint160(uint256(key))) == initiator || address(uint160(uint256(key))) == owner()
            : _allowList[key][initiator];
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
