// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "solady/auth/Ownable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/**
 * @title Extendable contract that allows an implementation to collect governance fees.
 */
abstract contract CanCollectGovernanceFee is Ownable {
    error GovernanceFeeTooHigh();
    error GovernanceFeeChangeNotReady();

    /**
     * @notice Governance fees has been distributed.
     */
    event GovernanceFeesDistributed(address indexed to, address[] tokens, uint256[] collectedAmounts);

    /**
     * @notice Governance fee will be changed shortly.
     */
    event NextGovernanceFee(uint64 nextGovernanceFee, uint64 nextGovernanceFeeTime);

    /**
     * @notice Governance fee changed. This fee is taken of the inputs.
     */
    event GovernanceFeeChanged(uint64 oldGovernanceFee, uint64 newGovernanceFee);

    uint64 public governanceFee = 0;
    uint64 public nextGovernanceFee = 0;
    uint64 public nextGovernanceFeeTime = type(uint64).max;
    uint64 constant GOVERNANCE_FEE_CHANGE_DELAY = 7 days;
    uint256 constant GOVERNANCE_FEE_DENOM = 10 ** 18;
    uint256 constant MAX_GOVERNANCE_FEE = 10 ** 18 * 0.1; // 10%

    constructor(
        address owner
    ) payable {
        _initializeOwner(owner);
    }

    /**
     * @notice Tokens collected by governance.
     * @dev Can be accessed through getGovernanceBalance.
     */
    mapping(address token => uint256 amount) internal _governanceTokens;

    function _resetGovernanceTokens(
        address token
    ) internal virtual {
        _governanceTokens[token] = 0;
    }

    /**
     * @notice Returns the amount of tokens collected by governance.
     * @dev View function for _governanceTokens storage slot.
     */
    function _getGovernanceBalance(
        address token
    ) internal view virtual returns (uint256 amountTokens) {
        return amountTokens = _governanceTokens[token];
    }

    function getGovernanceBalance(
        address token
    ) external view returns (uint256 amountTokens) {
        return _getGovernanceBalance(token);
    }

    /**
     * @notice Subtract the governance fee from an amount AND store the fee as the difference.
     * @dev This function sets the subtracted governance fee as collected. If you just want to
     * get the amount less fee, use `_calcFee`.
     * Ideally this function wouldn't be called if the fee is 0. Regardless, this function
     * won't modify storage if the collected fee becomes 0.
     * @param token for fee to be set for. Only impacts storage not computation.
     * @param amount for fee to be taken of.
     * @param fee to take of amount and set for token. Fee is provided as a variable to
     * save gas when used in a loop. The fee is out of 10**18.
     */
    function _collectGovernanceFee(address token, uint256 amount, uint256 fee) internal returns (uint256 governanceShare) {
        unchecked {
            // Get the governance share of the amountLessFee.
            governanceShare = _calcFee(amount, fee);

            // Only set storage if the fee is not 0.
            if (governanceShare != 0) _governanceTokens[token] = _governanceTokens[token] + governanceShare;
        }
    }

    /**
     * @notice Overload of _collectGovernanceFee reading the governance fee.
     */
    function _collectGovernanceFee(address token, uint256 amount) internal returns (uint256 governanceShare) {
        return governanceShare = _collectGovernanceFee(token, amount, governanceFee);
    }

    /**
     * @notice Helper function to compute the fee.
     * @param amount To compute fee of.
     * @param fee Fee to subtract from amount. Is percentage and GOVERNANCE_FEE_DENOM based.
     * @return amountFee Fee
     */
    function _calcFee(uint256 amount, uint256 fee) internal pure returns (uint256 amountFee) {
        unchecked {
            // Check if amount * fee overflows. If it does, don't take the fee.
            if (amount >= type(uint256).max / fee) return amountFee = 0;
            // The above check ensures that amount * fee < type(uint256).max.
            // amount >= amount * fee / GOVERNANCE_FEE_DENOM since fee < GOVERNANCE_FEE_DENOM
            return amountFee = amount * fee / GOVERNANCE_FEE_DENOM;
        }
    }

    /**
     * @notice Helper function to compute the fee.
     * The governanceFee is read from storage and passed to _calcFee(uint256,uint256)
     * @param amount To compute fee of.
     * @return amountFee Fee
     */
    function _calcFee(
        uint256 amount
    ) internal view returns (uint256 amountFee) {
        return _calcFee(amount, governanceFee);
    }

    /**
     * @notice Sets a new governanceFee. Is immediately applied to orders initiated after this call.
     * @param _nextGovernanceFee New governance fee. Is bounded by MAX_GOVERNANCE_FEE.
     */
    function setGovernanceFee(
        uint64 _nextGovernanceFee
    ) external onlyOwner {
        if (_nextGovernanceFee > MAX_GOVERNANCE_FEE) revert GovernanceFeeTooHigh();
        nextGovernanceFee = _nextGovernanceFee;
        nextGovernanceFeeTime = uint64(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY;

        emit NextGovernanceFee(nextGovernanceFee, nextGovernanceFeeTime);
    }

    /**
     * @notice Applies a scheduled governace fee change.
     */
    function applyGovernanceFee() external {
        if (block.timestamp < nextGovernanceFeeTime) revert GovernanceFeeChangeNotReady();
        uint64 oldGovernanceFee = governanceFee;
        governanceFee = nextGovernanceFee;

        emit GovernanceFeeChanged(oldGovernanceFee, nextGovernanceFee);
    }

    /**
     * @notice Distributes tokens allocated for governance.
     * @dev You cannot collect tokens for which the amount is 0.
     * Only the owner of the contract can call this, however, the owner can set another destination
     * as the target for the tokens. Pulls 100% of the collected tokens in the tokens list.
     * An example of a distribution mechanic would be requiring users to pay 1 Ether to call this function.
     * (from the owner contract). Once the fees are high enough someone would pay. This works kindof like
     * a dutch auction.
     * It may be important to check that collectedAmounts[i] > 0.
     * @param tokens List of tokens to collect governance fee from.
     * @param to Recipient of the tokens.
     * @return collectedAmounts Array of the collected governance tokens.
     */
    function distributeGovernanceTokens(address[] calldata tokens, address to) external virtual onlyOwner returns (uint256[] memory collectedAmounts) {
        unchecked {
            uint256 numTokens = tokens.length;
            collectedAmounts = new uint256[](numTokens);
            for (uint256 i = 0; i < numTokens; ++i) {
                address token = tokens[i];
                // Read the collected governance tokens and then set to 0 immediately.
                uint256 tokensToBeClaimed = _getGovernanceBalance(token);
                _resetGovernanceTokens(token);

                collectedAmounts[i] = tokensToBeClaimed;
                // Since we have "collected" the fee, it is expected that this function will go through.
                // Regardless, if it calls a non-contract address it doesn't really matter.
                SafeTransferLib.safeTransfer(token, to, tokensToBeClaimed);
            }
        }

        emit GovernanceFeesDistributed(to, tokens, collectedAmounts);
    }
}
