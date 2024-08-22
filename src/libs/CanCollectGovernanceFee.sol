// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "solady/src/auth/Ownable.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { GovernanceFeeChanged, GovernanceFeesCollected } from "../interfaces/Events.sol";

import { IsContractLib } from "./IsContractLib.sol";

abstract contract ICanCollectGovernanceFee {
    function _amountLessfee(uint256 amount) internal view virtual returns (uint256 amountLessFee);
}

/**
 * @title Extendable contract that allows an implementation to collect governance fees.
 */
abstract contract CanCollectGovernanceFee is Ownable, ICanCollectGovernanceFee {
    error GovernanceFeeTooHigh();
    error CannotCollect0Fees(address token);

    uint256 public governanceFee = 0;
    uint256 constant GOVERNANCE_FEE_DENUM = 10 ** 18;
    uint256 constant MAX_GOVERNANCE_FEE = 10 ** 18 * 0.25; // 25%

    constructor(address owner) {
        _initializeOwner(owner);
    }

    /**
     * @notice Tokens collected by governance.
     * @dev Can be accessed through getGovernanceTokens.
     */
    mapping(address token => uint256 amount) internal _governanceTokens;

    /**
     * @notice Returns the amount of tokens collected by governance.
     * @dev View function for _governanceTokens stoarge slot.
     */
    function getGovernanceTokens(address token) external view returns (uint256 amountTokens) {
        return amountTokens = _governanceTokens[token];
    }

    /**
     * @notice Subtract the governance fee from an amount AND store the fee as the difference.
     * @dev This function sets the subtracted governance fee as collected. If you just want to
     * get the amount less fee, use `_amountLessfee`.
     * Ideally this function wouldn't be called if the fee is 0. Regardless, this function
     * won't modify storage if the collected fee becomes 0.
     * @param token for fee to be set for. Only impacts storage not computation.
     * @param amount for fee to be taken of.
     * @param fee to take of amount and set for token. Fee is provided as a variable to
     * save gas when used in a loop. The fee is out of 10**18.
     * @return amountLessFee amount - fee.
     */
    function _collectGovernanceFee(
        address token,
        uint256 amount,
        uint256 fee
    ) internal returns (uint256 amountLessFee) {
        unchecked {
            // Compute the amount after fees has been subtracted.
            amountLessFee = _amountLessfee(amount, fee);
            // Compute the governance fee.
            uint256 governanceShare = amount - amountLessFee; // amount >= amountLessFee

            // Only set storage if the fee is not 0.
            if (governanceShare != 0) _governanceTokens[token] = governanceShare;
        }
    }

    /**
     * @notice Function overload of _collectGovernanceFee reading the governance fee.
     */
    function _collectGovernanceFee(address token, uint256 amount) internal returns (uint256 amountLessFee) {
        return amountLessFee = _collectGovernanceFee(token, amount, governanceFee);
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
     * @notice Helper function to compute an amount where the fee is subtracted.
     * @param amount To subtract fee from
     * @return amountLessFee Amount with fee subtracted from it.
     */
    function _amountLessfee(uint256 amount) internal view override returns (uint256 amountLessFee) {
        return _amountLessfee(amount, governanceFee);
    }

    /**
     * @notice Sets governanceFee
     * @param newGovernanceFee New governance fee. Is bounded by MAX_GOVERNANCE_FEE.
     */
    function setGovernanceFee(uint256 newGovernanceFee) external onlyOwner {
        if (newGovernanceFee > MAX_GOVERNANCE_FEE) revert GovernanceFeeTooHigh();
        uint256 oldGovernanceFee = governanceFee;
        governanceFee = newGovernanceFee;

        emit GovernanceFeeChanged(oldGovernanceFee, newGovernanceFee);
    }

    /**
     * @notice Distributes tokens allocated for governance.
     * @dev You cannot collect tokens for which the amount is 0.
     * Only the owner of the contract can call this, however, the owner can set another destination
     * as the target for the tokens.
     * Pulls 100% of the collected tokens in the tokens list.
     * An example of a distribution mechanic would be requiring users to pay 1 Ether to call this function.
     * (from the owner contract). Once the fees are high enough someone would pay. This works kindof like
     * a dutch auction.
     * @param tokens List of tokens to collect governance fee from.
     * Each token has to have getGovernanceTokens(tokens[i]) > 0.
     * @param to Recipient of the tokens.
     */
    function distributeGovernanceTokens(
        address[] calldata tokens,
        address to
    ) external onlyOwner returns (uint256[] memory collectedAmounts) {
        unchecked {
            uint256 numTokens = tokens.length;
            collectedAmounts = new uint256[](numTokens);
            for (uint256 i = 0; i < numTokens; ++i) {
                address token = tokens[i];
                // Read the collected governance tokens and then set to 0 immediately.
                uint256 tokensToBeClaimed = _governanceTokens[token];
                if (tokensToBeClaimed == 0) revert CannotCollect0Fees(token);
                _governanceTokens[token] = 0;

                collectedAmounts[i] = tokensToBeClaimed;
                // Since we have "collected" the fee, it is expected that this function will go through.
                // Regardless, if it calls a non-contract address it doesn't really matter.
                SafeTransferLib.safeTransfer(token, to, tokensToBeClaimed);
            }
        }

        emit GovernanceFeesCollected(to, tokens, collectedAmounts);
    }
}
