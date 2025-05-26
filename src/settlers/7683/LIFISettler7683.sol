// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";

import { ICatalystCallback } from "OIF/src/interfaces/ICatalystCallback.sol";
import { GaslessCrossChainOrder } from "OIF/src/interfaces/IERC7683.sol";
import { IOracle } from "OIF/src/interfaces/IOracle.sol";
import { MandateERC7683, Order7683Type, StandardOrder } from "OIF/src/settlers/7683/Order7683Type.sol";

import { Settler7683 } from "OIF/src/settlers/7683/Settler7683.sol";
import { MandateOutput } from "OIF/src/settlers/types/MandateOutputType.sol";

import { GovernanceFee } from "../../libs/GovernanceFee.sol";

/**
 * @title Catalyst Settler supporting The Compact
 * @notice This Catalyst Settler implementation uses The Compact as the deposit scheme.
 * It is a delivery first, inputs second scheme that allows users with a deposit inside The Compact.
 *
 * Users are expected to have an existing deposit inside the Compact or purposefully deposit for the intent.
 * They then needs to either register or sign a supported claim with the intent as the witness.
 * Without the deposit extension, this contract does not have a way to emit on-chain orders.
 *
 * This contract does not support fee on transfer tokens.
 */
contract LIFISettler7683 is Settler7683, GovernanceFee {
    constructor(
        address initialOwner
    ) Settler7683() {
        _initializeOwner(initialOwner);
    }

    function _domainNameAndVersion()
        internal
        pure
        virtual
        override
        returns (string memory name, string memory version)
    {
        name = "LIFISettlerEscrow7683";
        version = "7683LIFI1";
    }

    // TODO:
    /**
     * @dev This function can only be used when the intent described is a same-chain intent.
     * Set the solver as msg.sender (of this call). Timestamp will be collected from block.timestamp.
     */
    function openForAndFinalise(
        GaslessCrossChainOrder calldata order,
        bytes calldata signature,
        address destination,
        bytes calldata call
    ) external {
        // Validate the ERC7683 structure.
        _validateChain(order.originChainId);
        _validateDeadline(order.openDeadline);
        _validateDeadline(order.fillDeadline);

        StandardOrder memory compactOrder = Order7683Type.convertToCompactOrder(order);
        bytes32 orderId = Order7683Type.orderIdentifierMemory(compactOrder);

        if (_deposited[orderId] != OrderStatus.None) revert InvalidOrderStatus();
        // Mark order as deposited. If we can't make the deposit, we will
        // revert and it will unmark it. This acts as a reentry check.
        _deposited[orderId] = OrderStatus.Claimed;

        // Send input tokens to the provided destination so the tokens can be used for secondary purposes.
        // TODO: collect governance fee.
        _openFor(order, signature, orderId, compactOrder, destination);
        // Call the destination (if needed) so the caller can inject logic into our call.
        if (call.length > 0) ICatalystCallback(destination).inputsFilled(compactOrder.inputs, call);

        // Validate the fill. The solver may use the reentrance of the above line to execute the fill.
        _validateFills(compactOrder.localOracle, orderId, compactOrder.outputs);
    }

    //--- Output Proofs ---//

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Can take a list of solvers. Should be used as a secure alternative to _validateFills
     * if someone filled one of the outputs.
     */
    function _validateFills(address localOracle, bytes32 orderId, MandateOutput[] memory outputs) internal view {
        uint256 numOutputs = outputs.length;

        bytes memory proofSeries = new bytes(32 * 4 * numOutputs);
        for (uint256 i; i < numOutputs; ++i) {
            MandateOutput memory output = outputs[i];
            uint256 chainId = output.chainId;
            bytes32 remoteOracle = output.remoteOracle;
            bytes32 remoteFiller = output.remoteFiller;
            bytes32 payloadHash =
                _proofPayloadHashM(orderId, bytes32(uint256(uint160(msg.sender))), uint32(block.timestamp), output);

            assembly ("memory-safe") {
                let offset := add(add(proofSeries, 0x20), mul(i, 0x80))
                mstore(offset, chainId)
                mstore(add(offset, 0x20), remoteOracle)
                mstore(add(offset, 0x40), remoteFiller)
                mstore(add(offset, 0x60), payloadHash)
            }
        }
        IOracle(localOracle).efficientRequireProven(proofSeries);
    }

    // --- Finalise Orders --- //

    function finaliseSelf(
        StandardOrder calldata order,
        uint32[] calldata timestamps,
        bytes32 solver
    ) external override {
        _validateDeadline(order.fillDeadline);
        bytes32 orderId = Order7683Type.orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _validateOrderOwner(orderOwner);

        _finalise(order, orderId, solver, orderOwner);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solver, timestamps);
    }

    function finaliseTo(
        StandardOrder calldata order,
        uint32[] calldata timestamps,
        bytes32 solver,
        bytes32 destination,
        bytes calldata call
    ) external override {
        bytes32 orderId = Order7683Type.orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _validateOrderOwner(orderOwner);

        _finalise(order, orderId, solver, destination);
        if (call.length > 0) {
            ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);
        }

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solver, timestamps);
    }

    /**
     * @notice Finalises a cross-chain order on behalf of someone else
     * @dev This function serves to finalise intents on the origin chain. It has been assumed that assets have been
     * locked
     * inside The Compact and will be available to collect.
     * To properly collect the order details and proofs, the settler needs the solver identifier and the timestamps of
     * the fills.
     * @param order StandardOrder signed in conjunction with a Compact to form an order.
     */
    function finaliseFor(
        StandardOrder calldata order,
        uint32[] calldata timestamps,
        bytes32 solver,
        bytes32 destination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) external override {
        bytes32 orderId = Order7683Type.orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _allowExternalClaimant(
            orderId, EfficiencyLib.asSanitizedAddress(uint256(orderOwner)), destination, call, orderOwnerSignature
        );

        _finalise(order, orderId, solver, destination);
        if (call.length > 0) {
            ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);
        }

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solver, timestamps);
    }

    // -- Fallback Finalise Functions -- //
    // These functions are supposed to be used whenever someone else has filled 1 of the outputs of the order.
    // It allows the proper solver to still resolve the outputs correctly.
    // It does increase the gas cost :(
    // In all cases, the solvers needs to be provided in order of the outputs in order.
    // Important, this output generally matters in regards to the orderId. The solver of the first output is determined
    // to be the "orderOwner".

    function finaliseTo(
        StandardOrder calldata order,
        uint32[] calldata timestamps,
        bytes32[] calldata solvers,
        bytes32 destination,
        bytes calldata call
    ) external override {
        bytes32 orderId = Order7683Type.orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solvers[0], timestamps);
        _validateOrderOwner(orderOwner);

        _finalise(order, orderId, solvers[0], destination);
        if (call.length > 0) {
            ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);
        }

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solvers, timestamps);
    }

    /**
     * @notice Finalises a cross-chain order on behalf of someone else
     * @dev This function serves to finalise intents on the origin chain. It has been assumed that assets have been
     * locked inside The Compact and will be available to collect.
     * To properly collect the order details and proofs, the settler needs the solver identifier and the timestamps of
     * the fills.
     * @param order StandardOrder signed in conjunction with a Compact to form an order.
     */
    function finaliseFor(
        StandardOrder calldata order,
        uint32[] calldata timestamps,
        bytes32[] calldata solvers,
        bytes32 destination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) external override {
        bytes32 orderId = Order7683Type.orderIdentifier(order);
        {
            bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solvers[0], timestamps);
            _allowExternalClaimant(
                orderId, EfficiencyLib.asSanitizedAddress(uint256(orderOwner)), destination, call, orderOwnerSignature
            );

            _finalise(order, orderId, solvers[0], destination);
            if (call.length > 0) {
                ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(
                    order.inputs, call
                );
            }
        }

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solvers, timestamps);
    }

    //--- The Compact & Resource Locks ---//

    /**
     * @dev This function employs a local reentry guard: we check the order status and then we update it afterwards. This
     * is an important check as it is indeed to process external ERC20 transfers.
     */
    function _resolveLock(bytes32 orderId, uint256[2][] memory inputs, address solvedBy) internal virtual override {
        // Check the order status:
        if (_deposited[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();
        // Mark order as deposited. If we can't make the deposit, we will
        // revert and it will unmark it. This acts as a reentry check.
        _deposited[orderId] = OrderStatus.Claimed;

        uint256 fee = governanceFee;
        // We have now ensured that this point can only be reached once. We can now process the asset delivery.
        uint256 numInputs = inputs.length;
        for (uint256 i; i < numInputs; ++i) {
            uint256[2] memory input = inputs[i];
            address token = EfficiencyLib.asSanitizedAddress(input[0]);
            uint256 amount = input[1];

            uint256 calculatedFee = _calcFee(amount, fee);
            if (calculatedFee > 0) {
                SafeTransferLib.safeTransfer(token, owner(), calculatedFee);
                unchecked {
                    amount = amount - calculatedFee;
                }
            }

            SafeTransferLib.safeTransfer(token, solvedBy, amount);
        }
    }
}
