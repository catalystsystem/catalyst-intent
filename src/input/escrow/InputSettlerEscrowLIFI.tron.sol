// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.26;

import { SafeTransferLibTron } from "../../libs/SafeTransferLib.tron.sol";
import { InputSettlerEscrowLIFI } from "./InputSettlerEscrowLIFI.sol";
import { LibAddress } from "OIF/src/libs/LibAddress.sol";

/// @title LIFI Input Settler Escrow for Tron
/// @dev Overrides _resolveLock to use SafeTransferLibTron, which replaces broken transfer()
/// calls with an approve + transferFrom pattern for Tron USDT compatibility.
contract InputSettlerEscrowLIFITron is InputSettlerEscrowLIFI {
    using LibAddress for uint256;

    constructor(
        address initialOwner
    ) InputSettlerEscrowLIFI(initialOwner) { }

    function _domainName() internal pure override returns (string memory) {
        return "OIFEscrowLIFITron";
    }

    function _resolveLock(
        bytes32 orderId,
        uint256[2][] calldata inputs,
        address destination,
        OrderStatus newStatus
    ) internal virtual override {
        if (orderStatus[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();
        orderStatus[orderId] = newStatus;

        address _owner = owner();
        uint64 fee = _owner != address(0) ? governanceFee : 0;
        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            uint256[2] memory input = inputs[i];
            address token = input[0].fromIdentifier();
            uint256 amount = input[1];

            uint256 calculatedFee = _calcFee(amount, fee);
            if (calculatedFee > 0) {
                SafeTransferLibTron.safeTransfer(token, _owner, calculatedFee);
                unchecked {
                    amount = amount - calculatedFee;
                }
            }

            SafeTransferLibTron.safeTransfer(token, destination, amount);
        }
    }
}
