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

import { CatalystOrderData, OutputDescription } from "../CatalystOrderType.sol";
import { TheCompactOrderType, CatalystCompactFilledOrder } from "../TheCompactOrderType.sol";

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
    error InvalidTimestampLength();
    error NotOrderOwner();
    TheCompact public immutable COMPACT;

    constructor(address compact) {
        COMPACT = TheCompact(compact);
    }

    function _domainNameAndVersion() internal pure virtual override returns (string memory name, string memory version) {
        name = "CatalystSettler";
        version = "Compact1";
    }

    function _orderIdentifier(OnchainCrossChainOrder calldata order, address user, uint256 nonce) view override internal returns(bytes32) {
        return TheCompactOrderType.orderIdentifier(order, user, nonce);
    }

    function _orderIdentifier(GaslessCrossChainOrder calldata order) view override internal returns(bytes32) {
        return TheCompactOrderType.orderIdentifier(order);
    }

    function _orderIdentifier(CatalystCompactFilledOrder calldata order) view internal returns(bytes32) {
        return TheCompactOrderType.orderIdentifier(order);
    }

    function orderIdentifier(CatalystCompactFilledOrder calldata order) view external returns(bytes32) {
        return _orderIdentifier(order);
    }
    
    //--- Output Proofs ---//

    function _proofPayloadHash(
        bytes32 orderId,
        bytes32 solver,
        uint32 timestamp,
        OutputDescription calldata outputDescription
    ) pure internal returns (bytes32 outputHash) {
        // TODO: Ensure that there is a fallback if someone else filled one of the outputs.
        return keccak256(OutputEncodingLib.encodeOutputDescriptionIntoPayload(
            solver,
            timestamp,
            orderId,
            outputDescription
        ));
    }

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Notice that the solver of the first provided output is reported as the entire intent solver.
     */
    function _outputsFilled(address localOracle, bytes32 orderId, address solver, uint32[] calldata timestamps, OutputDescription[] calldata outputDescriptions) internal view {
        uint256 numOutputs = outputDescriptions.length;
        uint256 numTimestamps = timestamps.length;
        if (numTimestamps != numOutputs) revert InvalidTimestampLength();

        bytes memory proofSeries = new bytes(32 * 3 * numOutputs);
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription calldata output = outputDescriptions[i];
            uint256 chainId = output.chainId; 
            bytes32 remoteOracle = output.remoteOracle;
            bytes32 payloadHash = _proofPayloadHash(orderId, bytes32(uint256(uint160(solver))), timestamps[i], output);

            assembly ("memory-safe") {
                let offset := add(add(proofSeries, 0x20), mul(i, 0x60))
                mstore(offset, chainId)
                mstore(add(offset, 0x20), remoteOracle)
                mstore(add(offset, 0x40), payloadHash)
            }
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
            SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
            SafeTransferLib.safeApproveWithRetry(token, address(COMPACT), amount);
        }

        COMPACT.depositAndRegisterFor(user, idsAndAmounts, address(this), nonce, fillDeadline, TheCompactOrderType.BATCH_COMPACT_TYPE_HASH, TheCompactOrderType.orderHash(fillDeadline, orderData));

    }

    function open(
        OnchainCrossChainOrder calldata order
    ) external {
        _validateOrder(order);
        // fillDeadline is validated by theCompact
        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));

        // We need a nonce that doesn't overlap with an existing nonce. Using the blockhash is the best way to estimate a random nonce.
        uint256 randomNonce = uint256(blockhash(block.number));
        _open(msg.sender, randomNonce, order.fillDeadline, orderData);

        bytes32 orderId = _orderIdentifier(order, msg.sender, randomNonce);
        emit Open(orderId);
    }

    function openFor(GaslessCrossChainOrder calldata order, bytes calldata /* signature */, bytes calldata /* originFllerData */) external {
        _validateOrder(order);

        (CatalystOrderData memory orderData) = abi.decode(order.orderData, (CatalystOrderData));
        _open(order.user, order.nonce, order.fillDeadline, orderData);

        bytes32 orderId = _orderIdentifier(order);
        emit Open(orderId);
    }

    // --- Finalise Orders --- //

    function finaliseSelf(CatalystCompactFilledOrder calldata order, bytes calldata signatures, uint32[] calldata timestamps, address solver) external {
        bytes32 orderId = _orderIdentifier(order);
        
        address orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        if (orderOwner != msg.sender) revert NotOrderOwner();

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _outputsFilled(order.localOracle, orderId, solver, timestamps, order.outputs);

        bytes calldata sponsorSignature = BytesLib.toBytes(signatures, 0);
        bytes calldata allocatorSignature = BytesLib.toBytes(signatures, 1);
        // Payout inputs. (This also protects against re-entry calls.)
        _resolveLock(
            order, sponsorSignature, allocatorSignature, orderOwner
        );

        emit Open(orderId);
    }

    function finaliseTo(CatalystCompactFilledOrder calldata order, bytes calldata signatures, uint32[] calldata timestamps, address solver, address destination, bytes calldata call) external {
        bytes32 orderId = _orderIdentifier(order);
        
        address orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        if (orderOwner != msg.sender) revert NotOrderOwner();

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _outputsFilled(order.localOracle, orderId, solver, timestamps, order.outputs);

        bytes calldata sponsorSignature = BytesLib.toBytes(signatures, 0);
        bytes calldata allocatorSignature = BytesLib.toBytes(signatures, 1);
        // Payout inputs. (This also protects against re-entry calls.)
        _resolveLock(
            order, sponsorSignature, allocatorSignature, destination
        );

        if (call.length > 0) destination.call(call);

        emit Open(orderId);
    }

    
    /**
     * @notice Finalises a cross-chain order on behalf of someone else
     * @dev This function serves to finalise intents on the origin chain. It has been assumed that assets have been locked
     * inside The Compact and will be available to collect.
     * To properly collect the order details and proofs, the settler needs the solver identifier and the timestamps of the fills.
     * @param order GaslessCrossChainOrder signed in conjunction with a Compact to form an order. 
     * @param signatures A signature for the sponsor and the allocator. abi.encode(bytes(sponsorSignature), bytes(allocatorSignature))
     */
    function finaliseFor(CatalystCompactFilledOrder calldata order, bytes calldata signatures, uint32[] calldata timestamps, address solver, address destination, bytes calldata call, bytes calldata orderOwnerSignature) external {
        bytes32 orderId = _orderIdentifier(order);
        
        address orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _allowExternalClaimant(orderId, orderOwner, destination, call, orderOwnerSignature);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _outputsFilled(order.localOracle, orderId, solver, timestamps, order.outputs);

        bytes calldata sponsorSignature = BytesLib.toBytes(signatures, 0);
        bytes calldata allocatorSignature = BytesLib.toBytes(signatures, 1);
        // Payout inputs. (This also protects against re-entry calls.)
        _resolveLock(
            order, sponsorSignature, allocatorSignature, destination
        );

        if (call.length > 0) destination.call(call);

        emit Open(orderId);
    }

    //--- The Compact & Resource Locks ---//

    function _resolveLock(CatalystCompactFilledOrder calldata order, bytes calldata sponsorSignature, bytes calldata allocatorSignature, address solvedBy) internal virtual {
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

        bool success = COMPACT.claimAndWithdraw(BatchClaimWithWitness({
            allocatorSignature: allocatorSignature,
            sponsorSignature: sponsorSignature,
            sponsor: order.user,
            nonce: order.nonce,
            expires: order.fillDeadline,
            witness: TheCompactOrderType.orderHash(order),
            witnessTypestring: string(TheCompactOrderType.BATCH_SUB_TYPES),
            claims: claims,
            claimant: solvedBy
        }));
        require(success); // This should always be true.
    }
}