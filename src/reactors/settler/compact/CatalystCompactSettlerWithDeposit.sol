// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";
import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";
import { ResetPeriod } from "the-compact/src/types/ResetPeriod.sol";
import { Scope } from "the-compact/src/types/Scope.sol";

import { CatalystOrderData } from "../../CatalystOrderType.sol";
import { CatalystCompactSettler } from "./CatalystCompactSettler.sol";
import { TheCompactOrderType } from "./TheCompactOrderType.sol";

import { GaslessCrossChainOrder } from "../../../interfaces/IERC7683.sol";

/**
 * @notice Extends the Compact Settler with functionality to deposit into TheCompact
 * by providing the Catalyst order to this contract and providing appropriate allowances.
 * @dev 2 deposits pathways are provided:
 * - Deposit for a specific user providing the input tokens from msg.sender.
 * - Permit2 wrapping. If a proper signature for TheCompact is given, the whole order
 * can be submitted to this contract and the appropriate claim is set.
 */
contract CatalystCompactSettlerWithDeposit is CatalystCompactSettler {
    event Deposited(bytes32 orderId, GaslessCrossChainOrder order);

    constructor(
        address compact
    ) CatalystCompactSettler(compact) { }

    function _deposit(address user, uint256 nonce, uint256 fillDeadline, CatalystOrderData memory orderData, ResetPeriod resetPeriod) internal {
        uint256[2][] memory idsAndAmounts = orderData.inputs;
        uint256 numInputs = idsAndAmounts.length;
        // We need to collect the tokens from msg.sender.
        for (uint256 i; i < numInputs; ++i) {
            // Collect tokens from sender
            uint256[2] memory idAndAmount = idsAndAmounts[i];
            address token = EfficiencyLib.asSanitizedAddress(idAndAmount[0]);
            uint256 amount = idAndAmount[1];
            SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
            SafeTransferLib.safeApproveWithRetry(token, address(COMPACT), amount);
        }

        COMPACT.depositAndRegisterFor(user, idsAndAmounts, address(this), nonce, fillDeadline, TheCompactOrderType.BATCH_COMPACT_TYPE_HASH, TheCompactOrderType.orderHash(fillDeadline, orderData), resetPeriod);
    }

    function depositFor(GaslessCrossChainOrder calldata order, ResetPeriod resetPeriod) external {
        _validateOrder(order);

        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));
        _deposit(order.user, order.nonce, order.fillDeadline, orderData, resetPeriod);

        bytes32 orderId = _orderIdentifier(order);
        emit Deposited(orderId, order);
    }
}
