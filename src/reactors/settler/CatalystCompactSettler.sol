// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

import { BaseSettler } from "./BaseSettler.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    IOriginSettler,
    ResolvedCrossChainOrder,
    Open
} from "../../interfaces/IERC7683.sol";

import { CatalystOrderType, CatalystOrderData, OutputDescription } from "../../reactors/CatalystOrderType.sol";

import { BatchClaimWithWitness } from "the-compact/src/interfaces/ITheCompactClaims.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";

import { OutputEncodingLib } from "../../libs/OutputEncodingLib.sol";

import { BatchClaimComponent } from "the-compact/src/types/Components.sol";

import { IOracle } from "../../interfaces/IOracle.sol";

import { AllowOpenType } from "./AllowOpenType.sol";
import { BytesLib } from "../../libs/BytesLib.sol";

import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";

/**
 * @title Catalyst Reactor supporting The Compact
 * @notice The Catalyst Reactor implementation with The Compact as the deposit scheme.
 * This scheme is a remote first design pattern. 
 *
 * The current design iteration of the reactor does not support ERC7683 open / OnchainCrossChainOrder.
 */
contract CatalystCompactSettler is BaseSettler {
    error NotImplemented();
    TheCompact public immutable COMPACT;

    constructor(address compact) {
        COMPACT = TheCompact(compact);
    }

    function _domainNameAndVersion() internal pure virtual override returns (string memory name, string memory version) {
        name = "CatalystSettler";
        version = "Compact1";
    }

    function _orderIdentifier(OnchainCrossChainOrder calldata order) pure override internal returns(bytes32) {
        revert NotImplemented();
    }

    function _orderIdentifier(GaslessCrossChainOrder calldata order) pure override internal returns(bytes32) {
        return CatalystOrderType.orderIdentifier(order);
    }
    
    //--- Output Proofs ---//

    function _proofPayloadHash(
        bytes32 orderId,
        bytes32 solver,
        uint40 timestamp,
        OutputDescription memory outputDescription
    ) pure internal returns (bytes32 outputHash) {
        // TODO: Ensure that there is a fallback if someone else filled one of the outputs.
        return outputHash = keccak256(OutputEncodingLib.encodeOutputDescriptionIntoPayload(
            solver,
            timestamp,
            orderId,
            outputDescription
        ));
    }

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Function overload for outputFilled to allow proving multiple outputs in a single call.
     * Notice that the solver of the first provided output is reported as the entire intent solver.
     */
    function _outputsFilled(address localOracle, bytes32 orderId, address solver, uint40[] calldata timestamps, OutputDescription[] memory outputDescriptions) internal view {
        bytes memory proofSeries;
        
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

    function _open(address user, uint256 nonce, uint256 fillDeadline, CatalystOrderData memory orderData) internal {

        uint256[2][] memory idsAndAmounts = orderData.inputs;
        uint256 numInputs = idsAndAmounts.length;
        // We need to collect the tokens from msg.sender.
        for (uint256 i; i < numInputs; ++i) {
            // Collect tokens from sender
            uint256[2] memory idAndAmount = idsAndAmounts[i];
            address token = EfficiencyLib.asSanitizedAddress(idAndAmount[0]);
            uint256 amount = idAndAmount[1];
            SafeTransferLib.safeApproveWithRetry(token, address(COMPACT), amount);
            SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        }

        COMPACT.depositAndRegisterFor(user, idsAndAmounts, address(this), nonce, fillDeadline, CatalystOrderType.BATCH_COMPACT_TYPE_HASH, CatalystOrderType.orderHash(fillDeadline, orderData));

    }

    function open(
        OnchainCrossChainOrder calldata order
    ) external {
        // fillDeadline is validated by theCompact
        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));

        // We need a nonce that doesn't overlap with an existing nonce. Using the blockhash is the best way to estimate a random nonce.
        uint256 randomNonce = uint256(blockhash(block.number));
        _open(msg.sender, randomNonce, order.fillDeadline, orderData);
        
        // TODO: update
        emit Open(orderId);
    }

    function openFor(GaslessCrossChainOrder calldata order, bytes calldata /* signature */, bytes calldata /* originFllerData */) external {
        _validateOrder(order);
        bytes32 orderId = _orderIdentifier(order);

        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));
        _open(order.user, order.nonce, order.fillDeadline, orderData);

        // TODO: update
        emit Open(orderId);
    }

    function finaliseSelf(GaslessCrossChainOrder calldata order, bytes calldata signatures, uint40[] calldata timestamps, address solver) external {
        _validateOrder(order);
        bytes32 orderId = _orderIdentifier(order);
        
        address orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        require(orderOwner == msg.sender);

        // Decode the order data.
        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));

        // TODO: validate length of timestamps.
        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _outputsFilled(orderData.localOracle, orderId, solver, timestamps, orderData.outputs);

        bytes calldata sponsorSignature = BytesLib.toBytes(signatures, 0);
        bytes calldata allocatorSignature = BytesLib.toBytes(signatures, 1);
        // Payout inputs. (This also protects against re-entry calls.)
        _resolveLock(
            order, orderData, sponsorSignature, allocatorSignature, orderOwner
        );

        emit Open(orderId);
    }

    function finaliseTo(GaslessCrossChainOrder calldata order, bytes calldata signatures, uint40[] calldata timestamps, address solver, address destination, bytes calldata call) external {
        _validateOrder(order);
        bytes32 orderId = _orderIdentifier(order);
        
        address orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        require(orderOwner == msg.sender);

        // Decode the order data.
        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));

        // TODO: validate length of timestamps.
        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _outputsFilled(orderData.localOracle, orderId, solver, timestamps, orderData.outputs);

        bytes calldata sponsorSignature = BytesLib.toBytes(signatures, 0);
        bytes calldata allocatorSignature = BytesLib.toBytes(signatures, 1);
        // Payout inputs. (This also protects against re-entry calls.)
        _resolveLock(
            order, orderData, sponsorSignature, allocatorSignature, destination
        );

        if (call.length > 0) destination.call(call);

        emit Open(orderId);
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
     * @param signatures A signature for the sponsor and the allocator. abi.encode(bytes(sponsorSignature), bytes(allocatorSignature))
     */
    function finaliseFor(GaslessCrossChainOrder calldata order, bytes calldata signatures, uint40[] calldata timestamps, address solver, address destination, bytes calldata call, bytes calldata orderOwnerSignature) external {
        _validateOrder(order);
        bytes32 orderId = _orderIdentifier(order);
        
        address orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _allowExternalClaimant(orderId, orderOwner, destination, call, orderOwnerSignature);

        // Decode the order data.
        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));

        // TODO: validate length of timestamps.
        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _outputsFilled(orderData.localOracle, orderId, solver, timestamps, orderData.outputs);

        bytes calldata sponsorSignature = BytesLib.toBytes(signatures, 0);
        bytes calldata allocatorSignature = BytesLib.toBytes(signatures, 1);
        // Payout inputs. (This also protects against re-entry calls.)
        _resolveLock(
            order, orderData, sponsorSignature, allocatorSignature, destination
        );

        if (call.length > 0) destination.call(call);

        emit Open(orderId);
    }

    //--- The Compact & Resource Locks ---//

    function _resolveLock(GaslessCrossChainOrder calldata order, CatalystOrderData memory orderData, bytes calldata sponsorSignature, bytes calldata allocatorSignature, address solvedBy) internal virtual {
        uint256 numInputs = orderData.inputs.length;
        BatchClaimComponent[] memory claims = new BatchClaimComponent[](numInputs);
        uint256[2][] memory maxInputs = orderData.inputs;
        for (uint256 i; i < numInputs; ++i) {
            uint256[2] memory input = maxInputs[i];
            uint256 tokenId = input[0];
            uint256 allocatedAmount = input[1];
            claims[i] = BatchClaimComponent({
                id: tokenId, // The token ID of the ERC6909 token to allocate.
                allocatedAmount: allocatedAmount, // The original allocated amount of ERC6909 tokens.
                amount: allocatedAmount // The claimed token amount; specified by the arbiter.
            });
        }

        bool success = COMPACT.claimAndWithdraw(BatchClaimWithWitness({
            allocatorSignature: allocatorSignature,
            sponsorSignature: sponsorSignature,
            sponsor: order.user,
            nonce: order.nonce,
            expires: order.openDeadline,
            witness: CatalystOrderType.orderHash(order.fillDeadline, orderData),
            witnessTypestring: string(CatalystOrderType.BATCH_SUB_TYPES),
            claims: claims,
            claimant: solvedBy
        }));
        require(success); // This should always be true.
    }
}
