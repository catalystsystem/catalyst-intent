// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC7821 } from "solady/accounts/ERC7821.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";

/// @notice Basic EOA Batch Executor.
/// @dev Is based on Basic EOA Batch Executor by Solady (https://github.com/Vectorized/bebe), MIT License.
contract BasicEOABatchExecutor is ERC7821 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ERC1271 OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Validates the signature with ERC1271 return.
    /// This enables the EOA to still verify regular ECDSA signatures if the contract
    /// checks that it has code and calls this function instead of `ecrecover`.
    function isValidSignature(bytes32 hash, bytes calldata signature) public view virtual returns (bytes4 result) {
        bool success = ECDSA.recoverCalldata(hash, signature) == address(this);
        /// @solidity memory-safe-assembly
        assembly {
            // `success ? bytes4(keccak256("isValidSignature(bytes32,bytes)")) : 0xffffffff`.
            // We use `0xffffffff` for invalid, in convention with the reference implementation.
            result := shl(224, or(0x1626ba7e, sub(0, iszero(success))))
        }
    }

    /// @dev Executes the calls.
    /// Reverts and bubbles up error if any call fails.
    /// The `mode` and `executionData` are passed along in case there's a need to use them.
    function _execute(
        bytes32 mode,
        bytes calldata executionData,
        Call[] calldata calls,
        bytes calldata opData
    ) internal override {
        // Silence compiler warning on unused variables.
        mode = mode;
        executionData = executionData;
        // Very basic auth to only allow this contract to be called by itself.
        // Override this function to perform more complex auth with `opData`.
        if (opData.length == uint256(0)) {
            require(msg.sender == address(this));
            // Remember to return `_execute(calls, extraData)` when you override this function.
            return _execute(calls, bytes32(0));
        }
        revert(); // In your override, replace this with logic to operate on `opData`.
    }

    /// @dev Executes the call.
    /// Reverts and bubbles up error if any call fails.
    /// `extraData` can be any supplementary data (e.g. a memory pointer, some hash).
    function _execute(address target, uint256 value, bytes calldata data, bytes32 extraData) internal override {
        /// @solidity memory-safe-assembly
        assembly {
            extraData := extraData // Silence unused variable compiler warning.
            let m := mload(0x40) // Grab the free memory pointer.
            calldatacopy(m, data.offset, data.length)
            if iszero(call(gas(), target, value, m, data.length, codesize(), 0x00)) {
                // Bubble up the revert if the call reverts.
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
        }
    }
}
