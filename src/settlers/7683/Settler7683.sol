// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { BaseSettler } from "../BaseSettler.sol";
import { OutputDescription } from "src/settlers/types/OutputDescriptionType.sol";

import { ICatalystCallback } from "src/interfaces/ICatalystCallback.sol";
import { IOriginSettler, Open, Output, OnchainCrossChainOrder, GaslessCrossChainOrder, ResolvedCrossChainOrder, FillInstruction } from "src/interfaces/IERC7683.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { BytesLib } from "src/libs/BytesLib.sol";
import { IsContractLib } from "src/libs/IsContractLib.sol";
import { OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";
import { GovernanceFee } from "src/libs/GovernanceFee.sol";

import { CatalystCompactOrder, Order7683Type, MandateERC7683 } from "./Order7683Type.sol";

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
contract Settler7683 is BaseSettler, GovernanceFee {
    error NotImplemented();
    error NotOrderOwner();
    error DeadlinePassed();
    error InvalidTimestampLength();
    error OrderIdMismatch(bytes32 provided, bytes32 computed);
    error WrongChain(uint256 expected, uint256 actual);
    error InvalidOrderStatus();

    enum OrderStatus {
        None,
        Deposited,
        Claimed,
        Refunded
    }

    mapping(bytes32 orderId => OrderStatus) _deposited;

    // Address of the Permit2 contract.
    ISignatureTransfer constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function _domainNameAndVersion() internal pure virtual override returns (string memory name, string memory version) {
        name = "CatalystEscrow7683";
        version = "7683Escrow1";
    }

    // Generic order identifier
    function orderIdentifier(
        CatalystCompactOrder calldata compactOrder
    ) external view returns (bytes32) {
        return Order7683Type.orderIdentifier(compactOrder);
    }

    function orderIdentifier(
        OnchainCrossChainOrder calldata order
    ) view external returns(bytes32) {
        CatalystCompactOrder memory compactOrder = Order7683Type.convertToCompactOrder(msg.sender, order);
        return Order7683Type.orderIdentifierMemory(compactOrder);

    }

    function orderIdentifier(
        GaslessCrossChainOrder calldata order
    ) view external returns(bytes32) {
        CatalystCompactOrder memory compactOrder = Order7683Type.convertToCompactOrder(order);
        return Order7683Type.orderIdentifierMemory(compactOrder);
        
    }

    /**
     * @notice Checks that this is the right chain for the order.
     * @param chainId Expected chainId for order. Will be checked against block.chainid
     */
    function _validateChain(
        uint256 chainId
    ) internal view {
        if (block.chainid != chainId) revert WrongChain(block.chainid, chainId);
    }

    /**
     * @notice Checks that a timestamp has not expired.
     * @param timestamp The timestamp to validate that it is not less than block.timestamp
     */
    function _validateDeadline(
        uint256 timestamp
    ) internal view {
        if (block.timestamp > timestamp) revert DeadlinePassed();
    }

    function open(
        OnchainCrossChainOrder calldata order
    ) external {
        // Validate the ERC7683 structure.
        _validateDeadline(order.fillDeadline);

        // Get our orderdata.
        CatalystCompactOrder memory compactOrder = Order7683Type.convertToCompactOrder(msg.sender, order);
        bytes32 orderId = Order7683Type.orderIdentifierMemory(compactOrder);


        if (_deposited[orderId] != OrderStatus.None) revert InvalidOrderStatus();
        // Mark order as deposited. If we can't make the deposit, we will
        // revert and it will unmark it. This acts as a reentry check.
        _deposited[orderId] = OrderStatus.Deposited;


        // Collect input tokens. 
        uint256[2][] memory inputs = compactOrder.inputs;
        uint256 numInputs = inputs.length;
        for (uint256 i = 0; i < numInputs; ++i) {            uint256[2] memory input = inputs[i];
            address token = EfficiencyLib.asSanitizedAddress(input[0]);
            uint256 amount = input[1];
            SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        }

        emit Open(orderId, _resolve(uint32(0), orderId, compactOrder));
    }

    function _openFor(GaslessCrossChainOrder calldata order, bytes calldata signature, bytes32 orderId, CatalystCompactOrder memory compactOrder, address to) internal {

        uint256[2][] memory orderInputs = compactOrder.inputs;
        // Load the number of inputs. We need them to set the array size & convert each
        // input struct into a transferDetails struct.
        uint256 numInputs = orderInputs.length;
        ISignatureTransfer.TokenPermissions[] memory permitted = new ISignatureTransfer.TokenPermissions[](numInputs);
        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails = new ISignatureTransfer.SignatureTransferDetails[](numInputs);
        // Iterate through each input.
        for (uint256 i; i < numInputs; ++i) {
            uint256[2] memory orderInput = orderInputs[i];
            address token = EfficiencyLib.asSanitizedAddress(orderInput[0]);
            uint256 amount = orderInput[1];

            // Check if input tokens are contracts.
            IsContractLib.checkCodeSize(token);

            // Set the allowance. This is the explicit max allowed amount approved by the user.
            permitted[i] =
                ISignatureTransfer.TokenPermissions({ token: token, amount: amount });
            // Set our requested transfer. This has to be less than or equal to the allowance
            transferDetails[i] =
                ISignatureTransfer.SignatureTransferDetails({ to: to, requestedAmount: amount });
        }
        ISignatureTransfer.PermitBatchTransferFrom memory permitBatch =
            ISignatureTransfer.PermitBatchTransferFrom({ permitted: permitted, nonce: compactOrder.nonce, deadline: order.openDeadline });
        PERMIT2.permitWitnessTransferFrom(permitBatch, transferDetails, order.user, Order7683Type.witnessHash(order, compactOrder), string(Order7683Type.PERMIT2_ERC7683_GASLESS_CROSS_CHAIN_ORDER), signature);

        emit Open(orderId, _resolve(order.openDeadline, orderId, compactOrder));
    }

    function openFor(GaslessCrossChainOrder calldata order, bytes calldata signature, bytes calldata /* originFillerData */) external {
        // Validate the ERC7683 structure.
        _validateChain(order.originChainId);
        _validateDeadline(order.openDeadline);
        _validateDeadline(order.fillDeadline);

        CatalystCompactOrder memory compactOrder = Order7683Type.convertToCompactOrder(order);
        bytes32 orderId = Order7683Type.orderIdentifierMemory(compactOrder);


        if (_deposited[orderId] != OrderStatus.None) revert InvalidOrderStatus();
        // Mark order as deposited. If we can't make the deposit, we will
        // revert and it will unmark it. This acts as a reentry check.
        _deposited[orderId] = OrderStatus.Deposited;


        // Collect input tokens
        _openFor(order, signature, orderId, compactOrder, address(this));
    }

    /**
     * @dev This function can only be used when the intent described is a same-chain intent.
     * Set the solver as msg.sender (of this call). Timestamp will be collected from block.tiemstamp.
     */
    function openForAndFinalise(GaslessCrossChainOrder calldata order, bytes calldata signature, address destination, bytes calldata call) external {
        // Validate the ERC7683 structure.
        _validateChain(order.originChainId);
        _validateDeadline(order.openDeadline);
        _validateDeadline(order.fillDeadline);

        CatalystCompactOrder memory compactOrder = Order7683Type.convertToCompactOrder(order);
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

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(compactOrder.localOracle, orderId, compactOrder.outputs);
    }

    function _resolve(uint32 openDeadline, bytes32 orderId, CatalystCompactOrder memory compactOrder) internal pure returns (ResolvedCrossChainOrder memory) {
        uint256 chainId = compactOrder.originChainId;

        uint256[2][] memory orderInputs = compactOrder.inputs;
        uint256 numInputs = orderInputs.length;
        // Set input description.
        Output[] memory inputs = new Output[](numInputs);
        for (uint256 i; i < numInputs; ++i) {
            uint256[2] memory orderInput = orderInputs[i];
            uint256 token = orderInput[0];
            uint256 amount = orderInput[1];

            inputs[i] = Output({
                token: bytes32(token),
                amount: amount,
                recipient: bytes32(0),
                chainId: chainId
            });
        }

        OutputDescription[] memory orderOutputs = compactOrder.outputs;
        uint256 numOutputs = orderOutputs.length;
        // Set Output description.
        Output[] memory outputs = new Output[](numOutputs);
        // Set instructions
        FillInstruction[] memory instructions = new FillInstruction[](numOutputs);
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription memory orderOutput = orderOutputs[i];

            outputs[i] = Output({
                token: orderOutput.token,
                amount: orderOutput.amount,
                recipient:  orderOutput.recipient,
                chainId: orderOutput.chainId
            });

            instructions[i] = FillInstruction({
                destinationChainId: uint64(orderOutput.chainId),
                destinationSettler: orderOutput.remoteFiller,
                originData: abi.encode(orderOutput)
            });
        }

        return ResolvedCrossChainOrder({
            user: compactOrder.user,
            originChainId: compactOrder.originChainId,
            openDeadline: openDeadline,
            fillDeadline: compactOrder.fillDeadline,
            orderId: orderId,
            maxSpent: outputs,
            minReceived: inputs,
            fillInstructions: instructions
        });
    }


    function resolveFor(GaslessCrossChainOrder calldata order, bytes calldata /* originFillerData */) external view returns (ResolvedCrossChainOrder memory) {
        CatalystCompactOrder memory compactOrder = Order7683Type.convertToCompactOrder(order);
        bytes32 orderId = Order7683Type.orderIdentifierMemory(compactOrder);
        return _resolve(order.openDeadline, orderId, compactOrder);
    }

    function resolve(
        OnchainCrossChainOrder calldata order
    ) external view returns (ResolvedCrossChainOrder memory) {
        CatalystCompactOrder memory compactOrder = Order7683Type.convertToCompactOrder(msg.sender, order);
        bytes32 orderId = Order7683Type.orderIdentifierMemory(compactOrder);
        return _resolve(uint32(0), orderId, compactOrder);
    }


    //--- Output Proofs ---//

    function _proofPayloadHash(bytes32 orderId, bytes32 solver, uint32 timestamp, OutputDescription calldata outputDescription) internal pure returns (bytes32 outputHash) {
        return keccak256(OutputEncodingLib.encodeFillDescription(solver, orderId, timestamp, outputDescription));
    }

    function _proofPayloadHashM(bytes32 orderId, bytes32 solver, uint32 timestamp, OutputDescription memory outputDescription) internal pure returns (bytes32 outputHash) {
        return keccak256(OutputEncodingLib.encodeFillDescriptionM(solver, orderId, timestamp, outputDescription));
    }

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Can take a list of solvers. Should be used as a secure alternative to _validateFills
     * if someone filled one of the outputs.
     */
    function _validateFills(address localOracle, bytes32 orderId, OutputDescription[] memory outputDescriptions) internal view {
        uint256 numOutputs = outputDescriptions.length;

        bytes memory proofSeries = new bytes(32 * 4 * numOutputs);
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription memory output = outputDescriptions[i];
            uint256 chainId = output.chainId;
            bytes32 remoteOracle = output.remoteOracle;
            bytes32 remoteFiller = output.remoteFiller;
            bytes32 payloadHash = _proofPayloadHashM(orderId, bytes32(uint256(uint160(msg.sender))), uint32(block.timestamp), output);

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

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Can take a list of solvers. Should be used as a secure alternative to _validateFills
     * if someone filled one of the outputs.
     */
    function _validateFills(address localOracle, bytes32 orderId, bytes32[] calldata solvers, uint32[] calldata timestamps, OutputDescription[] calldata outputDescriptions) internal view {
        uint256 numOutputs = outputDescriptions.length;
        uint256 numTimestamps = timestamps.length;
        if (numTimestamps != numOutputs) revert InvalidTimestampLength();

        bytes memory proofSeries = new bytes(32 * 4 * numOutputs);
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription calldata output = outputDescriptions[i];
            uint256 chainId = output.chainId;
            bytes32 remoteOracle = output.remoteOracle;
            bytes32 remoteFiller = output.remoteFiller;
            bytes32 payloadHash = _proofPayloadHash(orderId, solvers[i], timestamps[i], output);

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

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Notice that the solver of the first provided output is reported as the entire intent solver.
     * This function returns true if the order contains no outputs.
     * That means any order that has no outputs specified can be claimed with no issues.
     */
    function _validateFills(address localOracle, bytes32 orderId, bytes32 solver, uint32[] calldata timestamps, OutputDescription[] calldata outputDescriptions) internal view {
        uint256 numOutputs = outputDescriptions.length;
        uint256 numTimestamps = timestamps.length;
        if (numTimestamps != numOutputs) revert InvalidTimestampLength();

        bytes memory proofSeries = new bytes(32 * 4 * numOutputs);
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription calldata output = outputDescriptions[i];
            uint256 chainId = output.chainId;
            bytes32 remoteOracle = output.remoteOracle;
            bytes32 remoteFiller = output.remoteFiller;
            bytes32 payloadHash = _proofPayloadHash(orderId, solver, timestamps[i], output);

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

    function _validateOrderOwner(
        bytes32 orderOwner
    ) internal view {
        // We need to cast orderOwner down. This is important to ensure that
        // the solver can opt-in to an compact transfer instead of withdrawal.
        if (EfficiencyLib.asSanitizedAddress(uint256(orderOwner)) != msg.sender) revert NotOrderOwner();
    }

    function _finalise(CatalystCompactOrder calldata order, bytes32 orderId, bytes32 solver, bytes32 destination) internal {
        // Payout inputs. (This also protects against re-entry calls.)
        _resolveLock(orderId, order.inputs, EfficiencyLib.asSanitizedAddress(uint256(destination)));

        emit Finalised(orderId, solver, destination);
    }

    function finaliseSelf(CatalystCompactOrder calldata order, uint32[] calldata timestamps, bytes32 solver) external {
        bytes32 orderId = Order7683Type.orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _validateOrderOwner(orderOwner);

        _finalise(order, orderId, solver, orderOwner);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order.localOracle, orderId, solver, timestamps, order.outputs);

    }

    function finaliseTo(CatalystCompactOrder calldata order, uint32[] calldata timestamps, bytes32 solver, bytes32 destination, bytes calldata call) external {
        bytes32 orderId = Order7683Type.orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _validateOrderOwner(orderOwner);

        _finalise(order, orderId, solver, destination);
        if (call.length > 0) ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order.localOracle, orderId, solver, timestamps, order.outputs);

    }

    /**
     * @notice Finalises a cross-chain order on behalf of someone else
     * @dev This function serves to finalise intents on the origin chain. It has been assumed that assets have been
     * locked
     * inside The Compact and will be available to collect.
     * To properly collect the order details and proofs, the settler needs the solver identifier and the timestamps of
     * the fills.
     * @param order CatalystCompactOrder signed in conjunction with a Compact to form an order.
     */
    function finaliseFor(
        CatalystCompactOrder calldata order,
        uint32[] calldata timestamps,
        bytes32 solver,
        bytes32 destination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) external {
        bytes32 orderId = Order7683Type.orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _allowExternalClaimant(orderId, EfficiencyLib.asSanitizedAddress(uint256(orderOwner)), destination, call, orderOwnerSignature);

        _finalise(order, orderId, solver, destination);
        if (call.length > 0) ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order.localOracle, orderId, solver, timestamps, order.outputs);

    }

    // -- Fallback Finalise Functions -- //
    // These functions are supposed to be used whenever someone else has filled 1 of the outputs of the order.
    // It allows the proper solver to still resolve the outputs correctly.
    // It does increase the gas cost :(
    // In all cases, the solvers needs to be provided in order of the outputs in order.
    // Important, this output generally matters in regards to the orderId. The solver of the first output is determined
    // to be the "orderOwner".

    function finaliseTo(CatalystCompactOrder calldata order, uint32[] calldata timestamps, bytes32[] calldata solvers, bytes32 destination, bytes calldata call) external {
        bytes32 orderId = Order7683Type.orderIdentifier(order);

        bytes32 orderOwner =_purchaseGetOrderOwner(orderId, solvers[0], timestamps);
        _validateOrderOwner(orderOwner);

        _finalise(order, orderId, solvers[0], destination);
        if (call.length > 0) ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order.localOracle, orderId, solvers, timestamps, order.outputs);

    }

    /**
     * @notice Finalises a cross-chain order on behalf of someone else
     * @dev This function serves to finalise intents on the origin chain. It has been assumed that assets have been
     * locked inside The Compact and will be available to collect.
     * To properly collect the order details and proofs, the settler needs the solver identifier and the timestamps of
     * the fills.
     * @param order CatalystCompactOrder signed in conjunction with a Compact to form an order.
     */
    function finaliseFor(
        CatalystCompactOrder calldata order,
        uint32[] calldata timestamps,
        bytes32[] calldata solvers,
        bytes32 destination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) external {
        bytes32 orderId = Order7683Type.orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solvers[0], timestamps);
        _allowExternalClaimant(orderId, EfficiencyLib.asSanitizedAddress(uint256(orderOwner)), destination, call, orderOwnerSignature);

        _finalise(order, orderId, solvers[0], destination);
        if (call.length > 0) ICatalystCallback(EfficiencyLib.asSanitizedAddress(uint256(destination))).inputsFilled(order.inputs, call);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order.localOracle, orderId, solvers, timestamps, order.outputs);
    }

    //--- The Compact & Resource Locks ---//

    /**
     * @dev This function employs a local reentry guard: we check the order status and then we update it afterwards. This is an important check as it is indeed to process external ERC20 transfers.
     */
    function _resolveLock(bytes32 orderId, uint256[2][] memory inputs, address solvedBy) internal virtual {
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
                SafeTransferLib.safeTransfer(token, solvedBy, calculatedFee);
                unchecked {
                    amount = amount - calculatedFee;
                }
            }

            SafeTransferLib.safeTransfer(token, solvedBy, amount);
        }
    }
}
