// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable } from "solady/src/auth/Ownable.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { GovernanceFeeChanged } from "../interfaces/Events.sol";

import { IsContractLib } from "./IsContractLib.sol";

/**
 * @title Extendable contract that allows an implementation to collect governance fees.
 */
abstract contract CanCollectGovernanceFee is Ownable {
    uint256 public governanceFee = 0;
    uint256 constant GOVERNANCE_FEE_DENUM = 10 ** 18;
    uint256 constant MAX_GOVERNANCE_FEE = 10 ** 18 * 0.25; // 25%

    mapping(address token => uint256 amount) internal _governanceTokens;

    /**
     * @notice Returns the amount collected for a given token.
     * @dev View function for _governanceTokens stoarge slot.
     */
    function getGovernanceTokens(address token) external view returns (uint256 amountTokens) {
        return amountTokens = _governanceTokens[token];
    }

    /**
     * @notice Function overload of _collectGovernanceFee reading the governance fee.
     */
    function _collectGovernanceFee(address token, uint256 amount) internal returns (uint256 amountLessFee) {
        return amountLessFee = _collectGovernanceFee(token, amount, governanceFee);
    }

    /**
     * @notice Subtract the governance fee from an amount AND store the fee as the difference.
     * @dev This function sets the subtracted governance fee as collected. If you just want to
     * get amountLessFee use `_amountLessfee`.
     * @param token for fee to be set for.
     * @param amount for fee to be taken of.
     * @param fee To take of amount and set for token. Fee is provided as a variable to
     * save gas when used in a loop.
     * @return amountLessFee amount - fee.
     */
    function _collectGovernanceFee(
        address token,
        uint256 amount,
        uint256 fee
    ) internal returns (uint256 amountLessFee) {
        unchecked {
            amountLessFee = _amountLessfee(amount, fee);
            // Set the governanceFee
            uint256 governanceShare = amount - amountLessFee; // amount >= amountLessFee
            if (governanceShare != 0) _governanceTokens[token] = governanceShare;
        }
    }

    /**
     * @notice Helper function to compute an amount where the fee is subtracted.
     * @param amount To subtract fee from
     * @param fee Fee to subtract from amount. Is percentage and GOVERNANCE_FEE_DENUM based.
     * @return amountLessFee Amount with fee subtracted from it.
     */
    function _amountLessfee(uint256 amount, uint256 fee) internal pure returns (uint256 amountLessFee) {
        unchecked {
            // Check if amount * fee overflows. If it does, don't take the fee.
            if (amount >= type(uint256).max / fee) return amountLessFee = amount;
            // The above check ensures that amount * fee < type(uint256).max.
            // amount >= amount * fee / GOVERNANCE_FEE_DENUM since fee < GOVERNANCE_FEE_DENUM
            amountLessFee = amount - amount * fee / GOVERNANCE_FEE_DENUM;
        }
    }

    /**
     * @notice Sets governanceFee
     * @param newGovernanceFee New governance fee. Is bounded by MAX_GOVERNANCE_FEE.
     */
    function setGovernanceFee(uint256 newGovernanceFee) external onlyOwner {
        if (newGovernanceFee > MAX_GOVERNANCE_FEE) revert("GovernanceFeeTooHigh()");
        uint256 oldGovernanceFee = governanceFee;
        governanceFee = newGovernanceFee;

        emit GovernanceFeeChanged(oldGovernanceFee, newGovernanceFee);
    }

    /**
     * @notice Distributes tokens allocated for governance.
     * @dev Only the owner of the contract can call this, however, the owner can set another destination
     * as the target for the tokens.
     * Pulls 100% of the collected tokens in the tokens list.
     * An example of a distribution mechanic would be requiring users to pay 1 Ether to call this function.
     * (from the owner contract). Once the fees are high enough someone would pay. This works kindof like
     * a dutch auction.
     * @param tokens List of tokens to collect governance fee from.
     * @param to Recipient of the tokens.
     */
    function distributeGovernanceTokens(
        address[] calldata tokens,
        address to
    ) external onlyOwner returns (uint256[] memory collectedTokens) {
        unchecked {
            uint256 numTokens = tokens.length;
            collectedTokens = new uint256[](numTokens);
            for (uint256 i = 0; i < numTokens; ++i) {
                address token = tokens[i];
                // Read the collected governance tokens and then set to 0 immediately.
                uint256 tokensToBeClaimed = _governanceTokens[token];
                _governanceTokens[token] = 0;

                collectedTokens[i] = tokensToBeClaimed;
                SafeTransferLib.safeTransfer(token, to, tokensToBeClaimed);
            }
        }
    }
}
