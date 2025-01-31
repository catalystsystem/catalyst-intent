// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { EIP712 } from "solady/utils/EIP712.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";

import { OutputDescription } from "../CatalystOrderType.sol";
import { OrderPurchaseType } from "./OrderPurchaseType.sol";

import { ICrossCatsCallback } from "../../interfaces/ICrossCatsCallback.sol";
import { IOracle } from "../../interfaces/IOracle.sol";

/**
 * @title Base Catalyst Order Intent Settler
 * @notice Defines common logic that can be reused by other settlers to support a variety
 * of asset management schemes.
 * @dev Implements the default CatalystOrderType and makes functions that are dedicated to that order type
 * available to implementing implementations.
 */
abstract contract BaseSettler is EIP712 {
    error AlreadyPurchased();
    error Expired();
    error InvalidPurchaser();
    error InvalidSigner();

    /// @notice Catalyst specific open event that replaces the ERC7683 one for cost purposes.
    event Open(bytes32 indexed orderId, bytes32 solver, address destination);
    event OrderPurchased(bytes32 indexed orderId, bytes32 solver, address purchaser);

    uint256 constant DISCOUNT_DENOM = 10 ** 18;

    struct Purchased {
        uint32 lastOrderTimestamp;
        address purchaser;
    }

    mapping(bytes32 solver => mapping(bytes32 orderId => Purchased)) public purchasedOrders;

    // --- Timestamp Helpers --- //

    /**
     * @notice Finds the largest timestamp in an array
     */
    function _maxTimestamp(
        uint32[] calldata timestamps
    ) internal pure returns (uint256 timestamp) {
        timestamp = timestamps[0];

        uint256 numTimestamps = timestamps.length;
        for (uint256 i = 1; i < numTimestamps; ++i) {
            uint32 nextTimestamp = timestamps[i];
            if (timestamp < nextTimestamp) timestamp = nextTimestamp;
        }
    }

    /**
     * @notice Finds the smallest timestamp in an array
     */
    function _minTimestamp(
        uint32[] calldata timestamps
    ) internal pure returns (uint32 timestamp) {
        timestamp = timestamps[0];

        uint256 numTimestamps = timestamps.length;
        for (uint256 i = 1; i < numTimestamps; ++i) {
            uint32 nextTimestamp = timestamps[i];
            if (timestamp > nextTimestamp) timestamp = nextTimestamp;
        }
    }

    // --- Order Purchase Helpers --- //

    /**
     * @notice Helper function to get the owner of order incase it may have been bought.
     * In case an order has been bought, and bought in time, the owner will be set to
     * the purchaser. Otherwise it will be set to the solver.
     */
    function _purchaseGetOrderOwner(bytes32 orderId, bytes32 solver, uint32[] calldata timestamps) internal view returns (address orderOwner) {
        // Check if the order has been purchased.
        Purchased storage purchaseDetails = purchasedOrders[solver][orderId];
        uint32 lastOrderTimestamp = purchaseDetails.lastOrderTimestamp;
        address purchaser = purchaseDetails.purchaser;

        if (purchaser != address(0)) {
            // Check if the order has been correctly purchased. We use the fill of the first timestamp
            // to gauge the result towards the purchaser
            uint256 orderTimestamp = _minTimestamp(timestamps);
            // If the timestamp of the order is less than lastOrderTimestamp, the order was purchased in time.
            if (lastOrderTimestamp > orderTimestamp) {
                return purchaser;
            }
        }
        return address(uint160(uint256(solver)));
    }

    function _purchaseOrder(
        bytes32 orderId,
        uint256[2][] calldata inputs,
        bytes32 orderSolvedByIdentifier,
        address purchaser,
        uint256 expiryTimestamp,
        address newDestination,
        bytes calldata call,
        uint48 discount,
        uint32 timeToBuy,
        bytes calldata solverSignature
    ) internal {
        if (purchaser == address(0)) revert InvalidPurchaser();
        if (expiryTimestamp < block.timestamp) revert Expired();

        // Check if the order has already been purchased.
        Purchased storage purchased = purchasedOrders[orderSolvedByIdentifier][orderId];
        if (purchased.purchaser != address(0)) revert AlreadyPurchased();

        // Reentry protection. Ensure that you can't reenter this contract.
        unchecked {
            // unchecked: uint32(block.timestamp) > timeToBuy => uint32(block.timestamp) - timeToBuy > 0.
            purchased.lastOrderTimestamp = timeToBuy < uint32(block.timestamp) ? uint32(block.timestamp) - timeToBuy : 0;
            purchased.purchaser = purchaser; // This disallows reentries through purchased.purchaser != address(0)
        }
        // We can now make external calls without allowing local reentries into this call.

        // We need to validate that the solver has approved someone else to purchase their order.
        address orderSolvedByAddress = address(uint160(uint256(orderSolvedByIdentifier)));

        bytes32 digest = _hashTypedData(OrderPurchaseType.hashOrderPurchase(orderId, address(this), newDestination, call, discount, timeToBuy));
        bool isValid = SignatureCheckerLib.isValidSignatureNow(orderSolvedByAddress, digest, solverSignature);
        if (!isValid) revert InvalidSigner();

        // Pay the input tokens to the solver.
        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            uint256[2] calldata input = inputs[i];
            uint256 tokenId = input[0];
            uint256 allocatedAmount = input[1];
            uint256 amountAfterDiscount = allocatedAmount * discount / DISCOUNT_DENOM;
            SafeTransferLib.safeTransferFrom(EfficiencyLib.asSanitizedAddress(tokenId), msg.sender, newDestination, amountAfterDiscount);
        }

        emit OrderPurchased(orderId, orderSolvedByIdentifier, purchaser);

        if (call.length > 0) ICrossCatsCallback(newDestination).inputsFilled(inputs, call);
    }
}
