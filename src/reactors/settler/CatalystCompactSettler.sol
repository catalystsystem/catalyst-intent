// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

import { BaseSettler } from "./BaseSettler.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    IOriginSettler,
    ResolvedCrossChainOrder,
    Open
} from "../../interfaces/IERC7683.sol";

import { CatalystOrderType, CatalystOrderData, OutputDescription, InputDescription } from "../../reactors/CatalystOrderType.sol";

import { BatchClaimWithWitness } from "the-compact/src/interfaces/ITheCompactClaims.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";

import { OutputEncodingLib } from "../../libs/OutputEncodingLib.sol";

import { BatchClaimComponent } from "the-compact/src/types/Components.sol";

import { IOracle } from "../../interfaces/IOracle.sol";

import { AllowOpenType } from "./AllowOpenType.sol";
import { BytesLib } from "../../libs/BytesLib.sol";

/**
 * @title Catalyst Reactor supporting The Compact
 * @notice The Catalyst Reactor implementation with The Compact as the deposit scheme.
 * This scheme is a remote first design pattern. 
 *
 * The current design iteration of the reactor does not support ERC7683 open / OnchainCrossChainOrder.
 */
contract CatalystCompactSettler is BaseSettler {
    error NotSupported();

    TheCompact public immutable COMPACT;

    constructor(address compact) {
        COMPACT = TheCompact(compact);
    }

    function _domainNameAndVersion() internal pure virtual override returns (string memory name, string memory version) {
        name = "CatalystSettler";
        version = "Compact1";
    }

    //--- Output Proofs ---//

    function _proofPayloadHash(
        bytes32 orderId,
        bytes32 solver,
        uint40 timestamp,
        OutputDescription memory outputDescription
    ) pure internal returns (bytes32 outputHash) {
        // TODO: Ensure that there is a fallback if someone else filled one of the outputs.
        return outputHash = keccak256(OutputEncodingLib.encodeFillDescription(
            solver,
            orderId,
            timestamp,
            outputDescription
        ));
    }

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Function overload for outputFilled to allow proving multiple outputs in a single call.
     * Notice that the solver of the first provided output is reported as the entire intent solver.
     */
    function _validateFills(address localOracle, bytes32 orderId, address solver, uint40[] calldata timestamps, OutputDescription[] memory outputDescriptions) internal view {
        bytes memory proofSeries;
        //TODO this should depend on the order type/filler used
        uint256 numOutputs = outputDescriptions.length;
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription memory output = outputDescriptions[i];
            proofSeries = abi.encodePacked(
                proofSeries,
                output.chainId,
                output.remoteOracle,
                _proofPayloadHash(orderId, bytes32(uint256(uint160(solver))), timestamps[i], output)
            );
        }
        IOracle(localOracle).efficientRequireProven(proofSeries);
    }

    function _allowExternalClaimant(
        bytes32 orderId,
        address orderOwner,
        address nextDestination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) internal view {
        bytes32 digest = _hashTypedData(AllowOpenType.hashAllowOpen(orderId, address(this), nextDestination, call));
        bool isValid = SignatureCheckerLib.isValidSignatureNowCalldata(orderOwner, digest, orderOwnerSignature);
        if (!isValid) revert InvalidSigner();
    }

    function open(
        OnchainCrossChainOrder calldata /* order */
    ) external pure {
        revert NotSupported();
    }

    
    /**
     * @notice Finalises a cross-chain order
     * @dev This function serves to finalise intents on the origin chain. It has been assumed that assets have been locked
     * inside The Compact and will be available to collect.
     * To properly collect the order details and proofs, the settler needs the solver identifier and the timestamps of the fills.
     * These are expected to have been provided as abi.encoded through originFllerData.
     * Notice, originFllerData can be encoded in 1 of 4 ways:
     * abi.encode(address(solver), uint40[](timestamps))
     *      if the caller is the solver.
     * abi.encode(address(solver), uint40[](timestamps), address(newDestination))
     *      if the caller is the solver and the assets should be delivered to another contract 
     * abi.encode(address(solver), uint40[](timestamps), address(newDestination), bytes(call))
     *      if the caller is the solver and the assets should be delivered to another contract and a call should be made to newDestination
     * abi.encode(address(solver), uint40[](timestamps), address(newDestination), bytes(call), bytes(orderOwnerSignature))
     *      if the caller isn't the solver (if they are, orderOwnerSignature will be ignored). Assets will be delivered to newDestination
     *      and if call.length > 0, a call to newDestination will be made.
     * @param order GaslessCrossChainOrder signed in conjunction with a Compact to form an order. 
     * @param signature A signature for the sponsor and the allocator. abi.encode(bytes(sponsorSignature), bytes(allocatorSignature))
     * @param originFllerData Custom filler data that is needed to correctly identify outputs but also allow for more flexible
     * execution. See @ dev for a description of how to encode it.
     */
    function openFor(GaslessCrossChainOrder calldata order, bytes calldata signature, bytes calldata originFllerData) external {
        _validateOrder(order);
        bytes32 orderId = _orderIdentifier(order);
        // Only the solver is allowed to unconditionally call open. If the caller is not the solver, the parameters needs to be signed.
        address solver;
        assembly ("memory-safe") {
            solver := calldataload(originFllerData.offset)
        }
        
        uint40[] calldata timestamps = BytesLib.toUint40Array(originFllerData, 1);
        address assetDestination = _purchaseGetOrderOwner(orderId, solver, timestamps);

        bool hasNewDestination;
        assembly ("memory-safe") { 
            // Check if the pointer for the timestamps is after the third item. If it is
            // then there isn't more data to be decoded. If there is, then there is more data.
            hasNewDestination := gt(calldataload(add(originFllerData.offset, 0x20)), 64)
        }
        if (hasNewDestination) {
            // abi.decode(originFllerData, (address, uint40[], address, bytes, bytes))
            address newDestination;
            assembly ("memory-safe") {
                newDestination := calldataload(add(originFllerData.offset, 0x40))
            }

            if (msg.sender != assetDestination) {
                bytes calldata call = BytesLib.toBytes(originFllerData, 3);
                bytes calldata orderOwnerSignature = BytesLib.toBytes(originFllerData, 4);
                _allowExternalClaimant(orderId, assetDestination, newDestination, call, orderOwnerSignature);
            }
            assetDestination = newDestination;
        }

        // Decode the order data.
        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));

        // TODO: validate length of timestamps.
        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(orderData.localOracle, orderId, solver, timestamps, orderData.outputs);

        bytes calldata sponsorSignature = BytesLib.toBytes(signature, 0);
        bytes calldata allocatorSignature = BytesLib.toBytes(signature, 1);
        // Payout inputs. (This also protects against re-entry calls.)
        _resolveLock(
            order, orderData, sponsorSignature, allocatorSignature, assetDestination
        );

        bool hasExternalCall;
        assembly ("memory-safe") {
            // Check if the pointer for the timestamps is after the fourth item. If it is
            // then there is calldata. to be executed.
            hasExternalCall := gt(calldataload(add(originFllerData.offset, 0x20)), 96)
        }
        if (hasExternalCall) {
            bytes calldata call = BytesLib.toBytes(originFllerData, 4);
            if (call.length > 0) assetDestination.call(call);
        }

        emit Open(orderId);
    }

    //--- The Compact & Resource Locks ---//

    function _resolveLock(GaslessCrossChainOrder calldata order, CatalystOrderData memory orderData, bytes calldata sponsorSignature, bytes calldata allocatorSignature, address solvedBy) internal virtual {
        uint256 numInputs = orderData.inputs.length;
        BatchClaimComponent[] memory claims = new BatchClaimComponent[](numInputs);
        InputDescription[] memory maxInputs = orderData.inputs;
        for (uint256 i; i < numInputs; ++i) {
            InputDescription memory input = orderData.inputs[i];
            claims[i] = BatchClaimComponent({
                id: input.tokenId, // The token ID of the ERC6909 token to allocate.
                allocatedAmount: maxInputs[i].amount, // The original allocated amount of ERC6909 tokens.
                amount: input.amount // The claimed token amount; specified by the arbiter.
            });
        }

        bool success = COMPACT.claimAndWithdraw(BatchClaimWithWitness({
            allocatorSignature: allocatorSignature,
            sponsorSignature: sponsorSignature,
            sponsor: order.user,
            nonce: order.nonce,
            expires: order.openDeadline,
            witness: CatalystOrderType.orderHash(order, orderData),
            witnessTypestring: string(CatalystOrderType.BATCH_SUB_TYPES),
            claims: claims,
            claimant: solvedBy
        }));
        require(success); // This should always be true.
    }
}
