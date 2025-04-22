// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";
import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";
import { ResetPeriod } from "the-compact/src/types/ResetPeriod.sol";
import { Scope } from "the-compact/src/types/Scope.sol";

import { CompactSettler } from "./CompactSettler.sol";
import { CatalystCompactOrder, TheCompactOrderType } from "./TheCompactOrderType.sol";

/**
 * @notice Extends the Compact Settler with functionality to deposit into TheCompact
 * by providing the Catalyst order to this contract and providing appropriate allowances.
 * @dev Using the Deposit for function, it is possible to convert an order into an associated
 * deposit in the Compact and emitting the order for consumption by solvers. Tokens are collected from msg.sender.
 *
 */
contract CompactSettlerWithDeposit is CompactSettler {
    event Deposited(bytes32 orderId, CatalystCompactOrder order);

    constructor(
        address compact
    ) CompactSettler(compact) { }

    function _domainNameAndVersion() internal pure virtual override returns (string memory name, string memory version) {
        name = "CatalystSettlerWithDeposit";
        version = "Compact1d";
    }

    function _deposit(address user, uint256 nonce, uint256 fillDeadline, CatalystCompactOrder calldata order) internal {
        uint256[2][] memory idsAndAmounts = order.inputs;
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

        COMPACT.depositAndRegisterFor(user, idsAndAmounts, address(this), nonce, fillDeadline, TheCompactOrderType.BATCH_COMPACT_TYPE_HASH, TheCompactOrderType.witnessHash(order));
    }

    function depositFor(
        CatalystCompactOrder calldata order
    ) external {
        _validateOrder(order);

        _deposit(order.user, order.nonce, order.fillDeadline, order);

        bytes32 orderId = _orderIdentifier(order);
        emit Deposited(orderId, order);
    }
}
