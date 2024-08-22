// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CrossChainOrder, ISettlementContract, Output } from "../../interfaces/ISettlementContract.sol";
import { OrderKey } from "../../interfaces/Structs.sol";

abstract contract ReactorAbstractions is ISettlementContract {
    //--- Override for implementation ---//

    /**
     * @notice Reactor Order implementations needs to implement this function to initiate their orders.
     * Return an orderKey with the relevant information to solve for.
     * @dev This function shouldn't check if the signature is correct but instead return information
     * to be used by _collectTokensViaPermit2 to verify the order (through PERMIT2).
     */
    function _initiate(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal virtual returns (OrderKey memory orderKey, bytes32 witness, string memory witnessTypeString);

    /**
     * @notice Logic function for resolveKey(...).
     * @dev Order implementations of this reactor are required to implement this function.
     */
    function _resolveKey(
        CrossChainOrder calldata order,
        bytes calldata fillerData
    ) internal view virtual returns (OrderKey memory);
}
