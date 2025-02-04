// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";
import { BatchClaimWithWitness } from "the-compact/src/interfaces/ITheCompactClaims.sol";
import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";
import { BatchClaimComponent } from "the-compact/src/types/Components.sol";

import { OutputDescription } from "src/settlers/types/OutputDescriptionType.sol";
import { BaseSettler } from "../BaseSettler.sol";
import { CatalystCompactOrder, TheCompactOrderType } from "./TheCompactOrderType.sol";

import { ICrossCatsCallback } from "src/interfaces/ICrossCatsCallback.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { BytesLib } from "src/libs/BytesLib.sol";
import { OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

/**
 * @title Catalyst Settler supporting The Compact
 * @notice This Catalyst Settler implementation uses The Compact as the deposit scheme.
 * It is a delivery first, inputs second scheme that allows users with a deposit inside The Compact.
 *
 * Users are expected to have an existing deposit inside the Compact or purposefully deposit for the intent.
 * They then needs to either register or sign a supported claim with the intent as the witness.
 * Without the deposit extension, this contract does not have a way to emit on-chain orders.
 */
contract CompactSettler is BaseSettler {
    error NotImplemented();
    error NotOrderOwner();
    error InitiateDeadlinePassed(); // 0x606ef7f5
    error InvalidTimestampLength();
    error OrderIdMismatch(bytes32 provided, bytes32 computed);
    error WrongChain(uint256 expected, uint256 actual); // 0x264363e1

    TheCompact public immutable COMPACT;

    constructor(
        address compact
    ) {
        COMPACT = TheCompact(compact);
    }

    function _domainNameAndVersion() internal pure virtual override returns (string memory name, string memory version) {
        name = "CatalystSettler";
        version = "Compact1";
    }

    // Generic order identifier

    function _orderIdentifier(
        CatalystCompactOrder calldata order
    ) internal view returns (bytes32) {
        return TheCompactOrderType.orderIdentifier(order);
    }

    function orderIdentifier(
        CatalystCompactOrder calldata order
    ) external view returns (bytes32) {
        return _orderIdentifier(order);
    }

    function _validateOrder(
        CatalystCompactOrder calldata order
    ) internal view {
        // Check that this is the right originChain
        if (block.chainid != order.originChainId) revert WrongChain(block.chainid, order.originChainId);
        // Check if the open deadline has been passed
        if (block.timestamp > order.fillDeadline) revert InitiateDeadlinePassed();
    }

    //--- Output Proofs ---//

    function _proofPayloadHash(bytes32 orderId, bytes32 solver, uint32 timestamp, OutputDescription calldata outputDescription) internal pure returns (bytes32 outputHash) {
        return keccak256(OutputEncodingLib.encodeFillDescription(solver, orderId, timestamp, outputDescription));
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

        bytes memory proofSeries = new bytes(32 * 3 * numOutputs);
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription calldata output = outputDescriptions[i];
            uint256 chainId = output.chainId;
            bytes32 remoteOracle = output.remoteOracle;
            bytes32 payloadHash = _proofPayloadHash(orderId, solvers[i], timestamps[i], output);

            assembly ("memory-safe") {
                let offset := add(add(proofSeries, 0x20), mul(i, 0x60))
                mstore(offset, chainId)
                mstore(add(offset, 0x20), remoteOracle)
                mstore(add(offset, 0x40), payloadHash)
            }
        }
        IOracle(localOracle).efficientRequireProven(proofSeries);
    }

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Notice that the solver of the first provided output is reported as the entire intent solver.
     */
    function _validateFills(address localOracle, bytes32 orderId, bytes32 solver, uint32[] calldata timestamps, OutputDescription[] calldata outputDescriptions) internal view {
        uint256 numOutputs = outputDescriptions.length;
        uint256 numTimestamps = timestamps.length;
        if (numTimestamps != numOutputs) revert InvalidTimestampLength();

        bytes memory proofSeries = new bytes(32 * 3 * numOutputs);
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription calldata output = outputDescriptions[i];
            uint256 chainId = output.chainId;
            bytes32 remoteOracle = output.remoteOracle;
            bytes32 payloadHash = _proofPayloadHash(orderId, solver, timestamps[i], output);

            assembly ("memory-safe") {
                let offset := add(add(proofSeries, 0x20), mul(i, 0x60))
                mstore(offset, chainId)
                mstore(add(offset, 0x20), remoteOracle)
                mstore(add(offset, 0x40), payloadHash)
            }
        }
        IOracle(localOracle).efficientRequireProven(proofSeries);
    }

    // --- Finalise Orders --- //


    function _finalise(CatalystCompactOrder calldata order, bytes calldata signatures, bytes32 orderId, bytes32 solver, address destination) internal {
        bytes calldata sponsorSignature = BytesLib.toBytes(signatures, 0);
        bytes calldata allocatorSignature = BytesLib.toBytes(signatures, 1);
        // Payout inputs. (This also protects against re-entry calls.)
        _resolveLock(order, sponsorSignature, allocatorSignature, destination);

        emit Finalised(orderId, solver, destination);
    }

    function finaliseSelf(CatalystCompactOrder calldata order, bytes calldata signatures, uint32[] calldata timestamps, bytes32 solver) external {
        bytes32 orderId = _orderIdentifier(order);

        address orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        if (orderOwner != msg.sender) revert NotOrderOwner();

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order.localOracle, orderId, solver, timestamps, order.outputs);

        _finalise(order, signatures, orderId, solver, orderOwner);
    }

    function finaliseTo(CatalystCompactOrder calldata order, bytes calldata signatures, uint32[] calldata timestamps, bytes32 solver, address destination, bytes calldata call) external {
        bytes32 orderId = _orderIdentifier(order);

        address orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        if (orderOwner != msg.sender) revert NotOrderOwner();

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order.localOracle, orderId, solver, timestamps, order.outputs);

        _finalise(order, signatures, orderId, solver, destination);

        if (call.length > 0) ICrossCatsCallback(destination).inputsFilled(order.inputs, call);
    }

    /**
     * @notice Finalises a cross-chain order on behalf of someone else
     * @dev This function serves to finalise intents on the origin chain. It has been assumed that assets have been
     * locked
     * inside The Compact and will be available to collect.
     * To properly collect the order details and proofs, the settler needs the solver identifier and the timestamps of
     * the fills.
     * @param order CatalystCompactOrder signed in conjunction with a Compact to form an order.
     * @param signatures A signature for the sponsor and the allocator. abi.encode(bytes(sponsorSignature),
     * bytes(allocatorSignature))
     */
    function finaliseFor(
        CatalystCompactOrder calldata order,
        bytes calldata signatures,
        uint32[] calldata timestamps,
        bytes32 solver,
        address destination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) external {
        bytes32 orderId = _orderIdentifier(order);

        address orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _allowExternalClaimant(orderId, orderOwner, destination, call, orderOwnerSignature);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order.localOracle, orderId, solver, timestamps, order.outputs);

        _finalise(order, signatures, orderId, solver, destination);

        if (call.length > 0) ICrossCatsCallback(destination).inputsFilled(order.inputs, call);
    }

    // -- Fallback Finalise Functions -- //
    // These functions are supposed to be used whenever someone else has filled 1 of the outputs of the order.
    // It allows the proper solver to still resolve the outputs correctly.
    // It does increase the gas cost :(
    // In all cases, the solvers needs to be provided in order of the outputs in order.
    // Important, this output generally matters in regards to the orderId. The solver of the first output is determined
    // to be the "orderOwner".

    function finaliseTo(CatalystCompactOrder calldata order, bytes calldata signatures, uint32[] calldata timestamps, bytes32[] calldata solvers, address destination, bytes calldata call) external {
        bytes32 orderId = _orderIdentifier(order);

        address orderOwner = _purchaseGetOrderOwner(orderId, solvers[0], timestamps);
        if (orderOwner != msg.sender) revert NotOrderOwner();

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order.localOracle, orderId, solvers, timestamps, order.outputs);

        _finalise(order, signatures, orderId, solvers[0], destination);

        if (call.length > 0) ICrossCatsCallback(destination).inputsFilled(order.inputs, call);
    }

    /**
     * @notice Finalises a cross-chain order on behalf of someone else
     * @dev This function serves to finalise intents on the origin chain. It has been assumed that assets have been
     * locked
     * inside The Compact and will be available to collect.
     * To properly collect the order details and proofs, the settler needs the solver identifier and the timestamps of
     * the fills.
     * @param order CatalystCompactOrder signed in conjunction with a Compact to form an order.
     * @param signatures A signature for the sponsor and the allocator. abi.encode(bytes(sponsorSignature),
     * bytes(allocatorSignature))
     */
    function finaliseFor(
        CatalystCompactOrder calldata order,
        bytes calldata signatures,
        uint32[] calldata timestamps,
        bytes32[] calldata solvers,
        address destination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) external {
        bytes32 orderId = _orderIdentifier(order);

        address orderOwner = _purchaseGetOrderOwner(orderId, solvers[0], timestamps);
        _allowExternalClaimant(orderId, orderOwner, destination, call, orderOwnerSignature);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order.localOracle, orderId, solvers, timestamps, order.outputs);

        _finalise(order, signatures, orderId, solvers[0], destination);

        if (call.length > 0) ICrossCatsCallback(destination).inputsFilled(order.inputs, call);
    }

    //--- The Compact & Resource Locks ---//

    function _resolveLock(CatalystCompactOrder calldata order, bytes calldata sponsorSignature, bytes calldata allocatorSignature, address solvedBy) internal virtual {
        uint256 numInputs = order.inputs.length;
        BatchClaimComponent[] memory claims = new BatchClaimComponent[](numInputs);
        uint256[2][] calldata maxInputs = order.inputs;
        for (uint256 i; i < numInputs; ++i) {
            uint256[2] calldata input = maxInputs[i];
            uint256 tokenId = input[0];
            uint256 allocatedAmount = input[1];
            claims[i] = BatchClaimComponent({
                id: tokenId, // The token ID of the ERC6909 token to allocate.
                allocatedAmount: allocatedAmount, // The original allocated amount of ERC6909 tokens.
                amount: allocatedAmount // The claimed token amount; specified by the arbiter.
             });
        }

        bool success = COMPACT.claimAndWithdraw(
            BatchClaimWithWitness({
                allocatorSignature: allocatorSignature,
                sponsorSignature: sponsorSignature,
                sponsor: order.user,
                nonce: order.nonce,
                expires: order.fillDeadline,
                witness: TheCompactOrderType.orderHash(order),
                witnessTypestring: string(TheCompactOrderType.BATCH_SUB_TYPES),
                claims: claims,
                claimant: solvedBy
            })
        );
        require(success); // This should always be true.
    }

    // --- Purchase Order --- //

    /**
     * @notice This function is called by whoever wants to buy an order from a filler.
     * If the order was purchased in time, then when the order is settled, the inputs will
     * go to the purchaser instead of the original solver.
     * @dev If you are buying a challenged order, ensure that you have sufficient time to prove the order or
     * your funds may be at risk and that you purchase it within the allocated time.
     * To purchase an order, it is required that you can produce a proper signature
     * from the solver that signs the purchase details.
     * @param orderSolvedByIdentifier Solver of the order. Is not validated, need to be correct otherwise
     * the purchase will be wasted.
     * @param expiryTimestamp Set to ensure if your transaction isn't mine quickly, you don't end
     * up purchasing an order that you cannot prove OR is not within the timeToBuy window.
     */
    function purchaseOrder(
        bytes32 orderId,
        CatalystCompactOrder calldata order,
        bytes32 orderSolvedByIdentifier,
        address purchaser,
        uint256 expiryTimestamp,
        address newDestination,
        bytes calldata call,
        uint48 discount,
        uint32 timeToBuy,
        bytes calldata solverSignature
    ) external {
        // Sanity check that the user thinks they are buying the right order.
        bytes32 computedOrderId = _orderIdentifier(order);
        if (computedOrderId != orderId) revert OrderIdMismatch(orderId, computedOrderId);

        uint256[2][] calldata inputs = order.inputs;
        _purchaseOrder(
            orderId,
            inputs,
            orderSolvedByIdentifier,
            purchaser,
            expiryTimestamp,
            newDestination,
            call,
            discount,
            timeToBuy,
            solverSignature
        );
    }
}
