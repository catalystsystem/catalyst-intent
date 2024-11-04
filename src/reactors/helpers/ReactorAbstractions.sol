// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CrossChainOrder, ISettlementContract, Input, Output } from "../../interfaces/ISettlementContract.sol";
import { OrderKey } from "../../interfaces/Structs.sol";

/**
 * @dev Override for implementation
 */
abstract contract ReactorAbstractions is ISettlementContract {
    /**
     * @notice Reactor Order implementations needs to implement this function to initiate their orders.
     * Return an orderKey with the relevant information to solve for.
     * @dev This function shouldn't check if the signature is correct but instead return information
     * to be used by _collectTokensViaPermit2 to verify the order (through PERMIT2).
     */
    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    )
        internal
        virtual
        returns (
            OrderKey memory orderKey,
            uint256[] memory permittedAmounts,
            bytes32 witness,
            string memory witnessTypeString
        );
    
    /**
     * @notice Returns the maximum inputs that a given order requires to be initiated.
     * Is used for the deposit function for composability.
     */
    function _getMaxInputs(
        CrossChainOrder calldata order
    )
        internal
        virtual
        pure
        returns(
            Input[] memory inputs
        );

    /**
     * @notice Logic function for resolveKey(...).
     * @dev Order implementations of this reactor are required to implement this function.
     */
    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal view virtual returns (OrderKey memory);
}
