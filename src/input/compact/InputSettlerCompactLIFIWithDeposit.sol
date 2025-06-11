// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";
import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";
import { ResetPeriod } from "the-compact/src/types/ResetPeriod.sol";
import { Scope } from "the-compact/src/types/Scope.sol";

import { InputSettlerCompactLIFI } from "./InputSettlerCompactLIFI.sol";
import { StandardOrder, StandardOrderType } from "OIF/src/input/types/StandardOrderType.sol";

/**
 * @notice Extends the Compact Settler with functionality to deposit into TheCompact
 * by providing the Catalyst order to this contract and providing appropriate allowances.
 * @dev Using the Deposit for function, it is possible to convert an order into an associated
 * deposit in the Compact and emitting the order for consumption by solvers. Tokens are collected from msg.sender.
 */
contract InputSettlerCompactLIFIWithDeposit is InputSettlerCompactLIFI {
    event Deposited(bytes32 orderId, StandardOrder order);

    error InitiateDeadlinePassed();
    error WrongChain(uint256 expected, uint256 provided);

    bytes32 constant STANDARD_ORDER_BATCH_COMPACT_TYPE_HASH = keccak256(
        bytes(
            "BatchCompact(address arbiter,address sponsor,uint256 nonce,uint256 expires,Lock[] commitments,Mandate mandate)Lock(bytes12 lockTag,address token,uint256 amount)Mandate(uint32 fillDeadline,address localOracle,MandateOutput[] outputs)MandateOutput(bytes32 oracle,bytes32 filler,uint256 chainId,bytes32 token,uint256 amount,bytes32 recipient,bytes call,bytes context)"
        )
    );

    constructor(address compact, address initialOwner) InputSettlerCompactLIFI(compact, initialOwner) { }

    /// @notice EIP712
    function _domainNameAndVersion()
        internal
        pure
        virtual
        override
        returns (string memory name, string memory version)
    {
        name = "InputSettlerCompact";
        version = "LIFI_1D";
    }

    function _validateChain(
        StandardOrder calldata order
    ) internal view {
        // Check that this is the right originChain
        if (block.chainid != order.originChainId) revert WrongChain(block.chainid, order.originChainId);
    }

    function _validateExpiry(
        StandardOrder calldata order
    ) internal view {
        // Check if the fill deadline has been passed
        if (block.timestamp > order.fillDeadline) revert InitiateDeadlinePassed();
        // Check if expiry has been passed
        if (block.timestamp > order.expires) revert InitiateDeadlinePassed();
    }

    function depositFor(
        StandardOrder calldata order
    ) external {
        _validateChain(order);
        _validateExpiry(order);

        _deposit(order.user, order.nonce, order.fillDeadline, order);

        bytes32 orderId = _orderIdentifier(order);
        emit Deposited(orderId, order);
    }

    function _deposit(address user, uint256 nonce, uint256 fillDeadline, StandardOrder calldata order) internal {
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

        COMPACT.batchDepositAndRegisterFor(
            user,
            idsAndAmounts,
            address(this),
            nonce,
            fillDeadline,
            STANDARD_ORDER_BATCH_COMPACT_TYPE_HASH,
            StandardOrderType.witnessHash(order)
        );
    }
}
