// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { EIP712 } from "solady/utils/EIP712.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";

import { AllowOpenType } from "./types/AllowOpenType.sol";
import { OrderPurchaseType } from "./types/OrderPurchaseType.sol";
import { OutputDescription } from "./types/OutputDescriptionType.sol";

import { ICatalystCallback } from "src/interfaces/ICatalystCallback.sol";
import { IOracle } from "src/interfaces/IOracle.sol";

/**
 * @title Base Catalyst Order Intent Settler
 * @notice Defines common logic that can be reused by other settlers to support a variety
 * of asset management schemes.
 * @dev Implements the default OutputDescriptionType and makes functions that are dedicated to that order type
 * available to implementing implementations.
 */
abstract contract BaseSettler is EIP712 {
    error AlreadyPurchased();
    error Expired();
    error InvalidPurchaser();
    error InvalidSigner();

    event Finalised(bytes32 indexed orderId, bytes32 solver, address destination);
    event OrderPurchased(bytes32 indexed orderId, bytes32 solver, address purchaser);

    uint256 constant DISCOUNT_DENOM = 10 ** 18;

    struct Purchased {
        uint32 lastOrderTimestamp;
        address purchaser;
    }

    mapping(bytes32 solver => mapping(bytes32 orderId => Purchased)) public purchasedOrders;

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

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

    // --- External Claimant --- //

    /**
     * @notice Check for a signed message by an order owner to allow someone else to redeem an order.
     * @dev See AllowOpenType.sol
     */
    function _allowExternalClaimant(bytes32 orderId, address orderOwner, address nextDestination, bytes calldata call, bytes calldata orderOwnerSignature) internal view {
        bytes32 digest = _hashTypedData(AllowOpenType.hashAllowOpen(orderId, address(this), nextDestination, call));
        bool isValid = SignatureCheckerLib.isValidSignatureNowCalldata(orderOwner, digest, orderOwnerSignature);
        if (!isValid) revert InvalidSigner();
    }

    // --- Order Purchase Helpers --- //

    /**
     * @notice Helper function to get the owner of order incase it may have been bought.
     * In case an order has been bought, and bought in time, the owner will be set to
     * the purchaser. Otherwise it will be set to the solver.
     */
    function _purchaseGetOrderOwner(bytes32 orderId, bytes32 solver, uint32[] calldata timestamps) internal returns (address orderOwner) {
        // Check if the order has been purchased.
        Purchased storage purchaseDetails = purchasedOrders[solver][orderId];
        uint32 lastOrderTimestamp = purchaseDetails.lastOrderTimestamp;
        address purchaser = purchaseDetails.purchaser;

        if (purchaser != address(0)) {
            // Check if the order has been correctly purchased. We use the fill of the last timestamp
            // to gauge the result towards the purchaser
            uint256 orderTimestamp = _maxTimestamp(timestamps);
            // If the timestamp of the order is less than or equal to lastOrderTimestamp, the order was purchased in time.
            if (lastOrderTimestamp <= orderTimestamp) {
                delete purchaseDetails.lastOrderTimestamp;
                delete purchaseDetails.purchaser;
                return purchaser;
            }
            delete purchaseDetails.lastOrderTimestamp;
            delete purchaseDetails.purchaser;
        }
        return address(uint160(uint256(solver)));
    }

    /**
     * @notice Helper functions for purchasing orders. Provides base logic, the integrating
     * implementation just needs to provide the correct orderId and inputs according to the order.
     * @param orderSolvedByIdentifier Solver of the order. Is not validated, need to be correct otherwise
     * the purchase will be wasted.
     * @param expiryTimestamp Set to ensure if your transaction isn't mine quickly, you don't end
     * up purchasing an order that you cannot prove OR is not within the timeToBuy window.
     */
    function _purchaseOrder(
        bytes32 orderId,
        uint256[2][] calldata inputs,
        bytes32 orderSolvedByIdentifier,
        address purchaser,
        uint256 expiryTimestamp,
        address newDestination,
        bytes calldata call,
        uint64 discount,
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
        bool isValid = SignatureCheckerLib.isValidSignatureNowCalldata(orderSolvedByAddress, digest, solverSignature);
        if (!isValid) revert InvalidSigner();

        // Pay the input tokens to the solver.
        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            uint256[2] calldata input = inputs[i];
            uint256 tokenId = input[0];
            uint256 allocatedAmount = input[1];
            uint256 amountAfterDiscount = allocatedAmount * (DISCOUNT_DENOM - discount) / DISCOUNT_DENOM; // If discount > DISCOUNT_DENOM the subtraction will throw an exception
            SafeTransferLib.safeTransferFrom(EfficiencyLib.asSanitizedAddress(tokenId), msg.sender, newDestination, amountAfterDiscount);
        }

        emit OrderPurchased(orderId, orderSolvedByIdentifier, purchaser);

        if (call.length > 0) ICatalystCallback(newDestination).inputsFilled(inputs, call);
    }
}
