// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { CanCollectGovernanceFee } from "../common/CanCollectGovernanceFee.sol";
import { CoinFiller } from "./CoinFiller.sol";

/**
 * @dev Override of the CoinFiller with a governance fee.
 */
contract CoinFillerWithFee is CoinFiller, CanCollectGovernanceFee {
    constructor(
        address owner
    ) payable CanCollectGovernanceFee(owner) { }

    function _preDeliveryHook(address, /* recipient */ address token, uint256 outputAmount) internal virtual override returns (uint256) {
        uint256 governanceShare = _calcFee(outputAmount);
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), governanceShare);
        return outputAmount;
    }

    function _getGovernanceBalance(
        address token
    ) internal view override returns (uint256 amountTokens) {
        return SafeTransferLib.balanceOf(token, address(this));
    }

    /**
     * @dev The true balance is used, not an internal tracker. As a result, the storage never needs to be reset.
     */
    function _resetGovernanceTokens(
        address token
    ) internal override { }
}
