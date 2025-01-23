// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IOracle } from "../../interfaces/IOracle.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    IOriginSettler,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "../../interfaces/IERC7683.sol";

import { CatalystOrderData, OutputDescription } from "../CatalystOrderType.sol";

import {
    InvalidSettlementAddress,
    WrongChain,
    InitiateDeadlinePassed
} from "../../interfaces/Errors.sol";

import { OrderPurchaseType } from "./OrderPurchaseType.sol";

import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";

import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { EIP712 } from "solady/utils/EIP712.sol";

/**
 * @title Base Catalyst Order Intent Settler
 * @notice Defines common logic that can be reused by other settlers to support a varity
 * of asset management schemes.
 * @dev Implements the default CatalystOrderType and makes functions that are dedicated to that order type 
 * available to implementing implementations.
 */
abstract contract BaseSettler is EIP712 {
    error AlreadyPurchased();
    error InvalidSigner();
    error InvalidPurchaser();
    error Expired();

    /// @notice Catalyst specific open event that replaces the ERC7683 one for cost purposes.
    event Open(bytes32 indexed orderId);
    event OrderPurchased(bytes32 indexed orderId, bytes32 solver, address purchaser);

    uint256 constant DISCOUNT_DENOM = 10**18;

    struct Purchased {
        uint40 lastOrderTimestamp;
        address purchaser;
    }

    mapping(bytes32 solver => mapping(bytes32 orderId => Purchased)) public purchasedOrders;

    // --- Hashing Orders --- //

    function _orderIdentifier(GaslessCrossChainOrder calldata order) pure virtual internal returns(bytes32);
    
    function _orderIdentifier(OnchainCrossChainOrder calldata order) pure virtual internal returns(bytes32);

    function orderIdentifier(GaslessCrossChainOrder calldata order) pure external returns(bytes32) {
        return _orderIdentifier(order);
    }

    function orderIdentifier(OnchainCrossChainOrder calldata order) pure external returns(bytes32) {
        return _orderIdentifier(order);
    }

    // --- Order Validation --- //

    function _validateOrder(GaslessCrossChainOrder calldata order) internal view {
        // Check that we are the settler for this order:
        if (address(this) != order.originSettler) revert InvalidSettlementAddress();
        // Check that this is the right originChain
        if (block.chainid != order.originChainId) revert WrongChain(block.chainid, order.originChainId);
        // Check if the open deadline has been passed
        if (block.timestamp > order.openDeadline) revert InitiateDeadlinePassed();
    }

    // --- Timestamp Helpers --- //

    /** @notice Finds the largest timestamp in an array */
    function _maxTimestamp(uint40[] calldata timestamps) internal pure returns (uint256 timestamp) {
        timestamp = timestamps[0]; 

        uint256 numTimestamps = timestamps.length;
        for (uint256 i = 1; i < numTimestamps; ++i) {
            uint40 nextTimestamp = timestamps[i];
            if (timestamp < nextTimestamp) timestamp = nextTimestamp;
        }
    }

    /** @notice Finds the smallest timestamp in an array */
    function _minTimestamp(uint40[] calldata timestamps) internal pure returns (uint40 timestamp) {
        timestamp = timestamps[0]; 

        uint256 numTimestamps = timestamps.length;
        for (uint256 i = 1; i < numTimestamps; ++i) {
            uint40 nextTimestamp = timestamps[i];
            if (timestamp > nextTimestamp) timestamp = nextTimestamp;
        }
    }

    // --- Order Purchase Helpers --- //

    /**
     * @notice Helper function to get the owner of order incase it may have been bought.
     * In case an order has been bought, and bought in time, the owner will be set to
     * the purchaser. Otherwise it will be set to the solver.
     */
    function _purchaseGetOrderOwner(
        bytes32 orderId,
        address solver,
        uint40[] calldata timestamps
    ) internal view returns (address orderOwner) {
        // Check if the order has been purchased.
        Purchased storage purchaseDetails = purchasedOrders[bytes32(uint256(uint160(solver)))][orderId];
        uint40 lastOrderTimestamp = purchaseDetails.lastOrderTimestamp;
        address purchaser = purchaseDetails.purchaser;

        if (lastOrderTimestamp > 0) {
            // Check if the order has been correctly purchased. We use the fill of the first timestamp
            // to gauge the result towards the purchaser
            uint256 orderTimestamp = _minTimestamp(timestamps);
            // If the timestamp of the order is less than lastOrderTimestamp, the order was purchased in time.
            if (lastOrderTimestamp > orderTimestamp) {
                return purchaser;
            }
        }
        return solver;
    }

    /**
     * @notice This function is called by whoever wants to buy an order from a filler.
     * If the order was purchased in time, then when the order is settled, the inputs will
     * go to the purchaser instead of the original solver.
     * @dev If you are buying a challenged order, ensure that you have sufficient time to prove the order or
     * your funds may be at risk and that you purchase it within the allocated time.
     * To purchase an order, it is required that you can produce a proper signature
     * from the solver that signes the purchase details.
     * @param orderSolvedByIdentifier Solver of the order. Is not validated, need to be correct otherwise
     * the purchase will be wasted.
     * @param expiryTimestamp Set to ensure if your transaction isn't mine quickly, you don't end
     * up purchasing an order that you cannot prove OR is not within the timeToBuy window.
     */
    function purchaseOrder(
        bytes32 orderSolvedByIdentifier,
        GaslessCrossChainOrder calldata order,
        address purchaser,
        uint256 expiryTimestamp,
        address newDestination,
        bytes calldata call,
        uint48 discount,
        uint40 timeToBuy,
        bytes calldata solverSignature
    ) external {
        if (purchaser == address(0)) revert InvalidPurchaser();
        if (expiryTimestamp < block.timestamp) revert Expired();

        bytes32 orderId = _orderIdentifier(order);

        // Check if the order has already been purchased.
        Purchased storage purchased = purchasedOrders[orderSolvedByIdentifier][orderId];
        if (purchased.purchaser != address(0)) revert AlreadyPurchased();

        // Reentry protection. Ensure that you can't reenter this contract.
        unchecked {
            // unchecked: uint40(block.timestamp) > timeToBuy => uint40(block.timestamp) - timeToBuy > 0.
            purchased.lastOrderTimestamp = timeToBuy < uint40(block.timestamp) ? uint40(block.timestamp) - timeToBuy : 0;
            purchased.purchaser = purchaser; // This disallows reentries through purchased.purchaser != address(0) 
        }
        // We can now make external calls without allowing local reentries into this call.

        // We need to validate that the solver has approved someone else to purchase their order.
        address orderSolvedByAddress = address(uint160(uint256(orderSolvedByIdentifier)));

        bytes32 digest = _hashTypedData(OrderPurchaseType.hashOrderPurchase(
            orderId,
            address(this),
            newDestination,
            call,
            discount,
            timeToBuy
        ));
        bool isValid = SignatureCheckerLib.isValidSignatureNow(orderSolvedByAddress, digest, solverSignature);
        if (!isValid) revert InvalidSigner();

        // Pay the input tokens to the solver.
        CatalystOrderData memory orderData = abi.decode(order.orderData, (CatalystOrderData));
        uint256[2][] memory inputs = orderData.inputs;
        uint256 numInputs = orderData.inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            uint256[2] memory input = inputs[i];
            uint256 tokenId = input[0];
            uint256 allocatedAmount = input[1];
            uint256 amountAfterDiscount = allocatedAmount * discount / DISCOUNT_DENOM;
            SafeTransferLib.safeTransferFrom(
                EfficiencyLib.asSanitizedAddress(tokenId),
                msg.sender,
                newDestination,
                amountAfterDiscount
            );
        }

        if (call.length > 0) newDestination.call(call);

        emit OrderPurchased(orderId, orderSolvedByIdentifier, purchaser);
    }

    //--- ERC7683 Resolvers ---//

    function _resolve(
        CatalystOrderData memory orderData,
        address filler
    ) internal view virtual returns (Output[] memory maxSpent, FillInstruction[] memory fillInstructions, Output[] memory minReceived) {
        uint256 numOutputs = orderData.outputs.length;
        maxSpent = new Output[](numOutputs);
        
        // If the output list is sorted by chains, this list is unqiue and optimal.
        OutputDescription[] memory outputs = orderData.outputs;
        fillInstructions = new FillInstruction[](numOutputs);
        for (uint256 i = 0; i < numOutputs; ++i) {
            OutputDescription memory catalystOutput = outputs[i];
            uint256 chainId = catalystOutput.chainId;
            maxSpent[i] = Output({
                token: catalystOutput.token,
                amount: catalystOutput.amount,
                recipient: catalystOutput.recipient,
                chainId: chainId
            });
            fillInstructions[i] = FillInstruction({
                destinationChainId: uint64(chainId),
                destinationSettler: catalystOutput.remoteOracle,
                originData: abi.encode(catalystOutput)
            });
        }

        // fillerOutputs are of the Output type and as a result, we can't just
        // load swapperInputs into fillerOutputs. As a result, we need to parse
        // the individual inputs and make a new struct.
        uint256[2][] memory inputs = orderData.inputs;
        uint256 numInputs = inputs.length;
        minReceived = new Output[](numInputs);
        unchecked {
            for (uint256 i; i < numInputs; ++i) {
                uint256[2] memory input = inputs[i];
                uint256 tokenId = input[0];
                uint256 allocatedAmount = input[1];
                minReceived[i] = Output({
                    token: bytes32(tokenId),
                    amount: allocatedAmount,
                    recipient: bytes32(uint256(uint160(filler))),
                    chainId: uint32(block.chainid)
                });
            }
        }
    }

    /**
     * @notice Resolves an order into an ERC-7683 compatible order struct.
     * By default relies on _resolveKey to convert OrderKey into a ResolvedCrossChainOrder
     * @dev Can be overwritten if there isn't a translation of an orderKey into resolvedOrder.
     * @param order CrossChainOrder to resolve.
     * @return resolvedOrder ERC-7683 compatible order description, including the inputs and outputs of the order
     */
    function _resolve(
        GaslessCrossChainOrder calldata order,
        address filler
    ) internal view virtual returns (ResolvedCrossChainOrder memory resolvedOrder) {
        CatalystOrderData memory orderData = abi.decode(order.orderData, (CatalystOrderData));

        (Output[] memory maxSpent, FillInstruction[] memory fillInstructions, Output[] memory minReceived) = _resolve(orderData, filler);

        // Lastly, complete the ResolvedCrossChainOrder struct.
        resolvedOrder = ResolvedCrossChainOrder({
            user: order.user,
            originChainId: order.originChainId,
            openDeadline: order.openDeadline,
            fillDeadline: order.fillDeadline,
            orderId: _orderIdentifier(order),
            maxSpent: maxSpent,
            minReceived: minReceived,
            fillInstructions: fillInstructions
        });
    }

    function _resolve(
        OnchainCrossChainOrder calldata order,
        address filler
    ) internal view virtual returns (ResolvedCrossChainOrder memory resolvedOrder) {
        CatalystOrderData memory orderData = abi.decode(order.orderData, (CatalystOrderData));

        (Output[] memory maxSpent, FillInstruction[] memory fillInstructions, Output[] memory minReceived) = _resolve(orderData, filler);

        // Lastly, complete the ResolvedCrossChainOrder struct.
        resolvedOrder = ResolvedCrossChainOrder({
            user: address(0),
            originChainId: block.chainid,
            openDeadline: 0,
            fillDeadline: order.fillDeadline,
            orderId: _orderIdentifier(order),
            maxSpent: maxSpent,
            minReceived: minReceived,
            fillInstructions: fillInstructions
        });
    }

    /**
     * @notice ERC-7683: Resolves a specific CrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param order CrossChainOrder to resolve.
     * @return resolvedOrder ERC-7683 compatible order description, including the inputs and outputs of the order
     */
    function resolve(
        OnchainCrossChainOrder calldata order
    ) external view returns (ResolvedCrossChainOrder memory resolvedOrder) {
        return _resolve(order, address(0));
    }

    function resolveFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata /* signature */,
        bytes calldata /* originFllerData */
    ) external view returns (ResolvedCrossChainOrder memory resolvedOrder) {
        return _resolve(order, address(0));
    }
}
