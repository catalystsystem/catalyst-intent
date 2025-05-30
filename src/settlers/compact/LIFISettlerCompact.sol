// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";
import { IdLib } from "the-compact/src/lib/IdLib.sol";
import { BatchClaim } from "the-compact/src/types/BatchClaims.sol";
import { BatchClaimComponent, Component } from "the-compact/src/types/Components.sol";

import { ICatalystCallback } from "OIF/src/interfaces/ICatalystCallback.sol";
import { SettlerCompact } from "OIF/src/settlers/compact/SettlerCompact.sol";
import { StandardOrder, StandardOrderType } from "OIF/src/settlers/types/StandardOrderType.sol";

import { GovernanceFee } from "../../libs/GovernanceFee.sol";

/**
 * @title Catalyst Settler supporting The Compact
 * @notice This Catalyst Settler implementation uses The Compact as the deposit scheme.
 * It is a delivery first, inputs second scheme that allows users with a deposit inside The Compact.
 *
 * Users are expected to have an existing deposit inside the Compact or purposefully deposit for the intent.
 * They then need to either register or sign a supported claim with the intent outputs as the witness.
 * Without the deposit extension, this contract does not have a way to emit on-chain orders.
 *
 * The ownable component of the smart contract is only used for fees.
 */
contract LIFISettlerCompact is SettlerCompact, GovernanceFee {
    constructor(address compact, address initialOwner) SettlerCompact(compact) {
        _initializeOwner(initialOwner);
    }

    /**
     * @notice EIP712
     */
    function _domainNameAndVersion()
        internal
        pure
        virtual
        override
        returns (string memory name, string memory version)
    {
        name = "LIFISettlerCompact";
        version = "CompactLIFI1";
    }

    function finaliseSelf(
        StandardOrder calldata order,
        bytes calldata signatures,
        uint32[] calldata timestamps,
        bytes32 solver
    ) external override {
        bytes32 orderId = _orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _validateOrderOwner(orderOwner);

        // Deliver outputs before the order has been finalised.
        _finalise(order, signatures, orderId, solver, orderOwner);

        // Check if the outputs have been proven according to the oracles.
        // This call will revert if not.
        _validateFills(order, orderId, solver, timestamps);
    }

    function finaliseTo(
        StandardOrder calldata order,
        bytes calldata signatures,
        uint32[] calldata timestamps,
        bytes32 solver,
        bytes32 destination,
        bytes calldata call
    ) external override {
        bytes32 orderId = _orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _validateOrderOwner(orderOwner);

        // Deliver outputs before the order has been finalised.
        _finalise(order, signatures, orderId, solver, destination);
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
     * locked inside The Compact and will be available to collect. To properly collect the order details and proofs,
     * the settler needs the solver identifier and the timestamps of the fills.
     * @param order StandardOrder signed in conjunction with a Compact to form an order.
     * @param signatures A signature for the sponsor and the allocator. abi.encode(bytes(sponsorSignature),
     * bytes(allocatorData))
     */
    function finaliseFor(
        StandardOrder calldata order,
        bytes calldata signatures,
        uint32[] calldata timestamps,
        bytes32 solver,
        bytes32 destination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) external override {
        bytes32 orderId = _orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solver, timestamps);
        _allowExternalClaimant(
            orderId, EfficiencyLib.asSanitizedAddress(uint256(orderOwner)), destination, call, orderOwnerSignature
        );

        // Deliver outputs before the order has been finalised.'
        _finalise(order, signatures, orderId, solver, destination);
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
        bytes calldata signatures,
        uint32[] calldata timestamps,
        bytes32[] memory solvers,
        bytes32 destination,
        bytes calldata call
    ) external override {
        bytes32 orderId = _orderIdentifier(order);

        bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solvers[0], timestamps);
        _validateOrderOwner(orderOwner);

        // Deliver outputs before the order has been finalised.
        _finalise(order, signatures, orderId, solvers[0], destination);
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
     * locked inside The Compact and will be available to collect. To properly collect the order details and proofs,
     * the settler needs the solver identifier and the timestamps of the fills.
     * @param order StandardOrder signed in conjunction with a Compact to form an order.
     * @param signatures A signature for the sponsor and the allocator.
     *  abi.encode(bytes(sponsorSignature), bytes(allocatorData))
     */
    function finaliseFor(
        StandardOrder calldata order,
        bytes calldata signatures,
        uint32[] calldata timestamps,
        bytes32[] memory solvers,
        bytes32 destination,
        bytes calldata call,
        bytes calldata orderOwnerSignature
    ) external override {
        bytes32 orderId = _orderIdentifier(order);

        {
            bytes32 orderOwner = _purchaseGetOrderOwner(orderId, solvers[0], timestamps);
            _allowExternalClaimant(
                orderId, EfficiencyLib.asSanitizedAddress(uint256(orderOwner)), destination, call, orderOwnerSignature
            );

            // Deliver outputs before the order has been finalised.
            _finalise(order, signatures, orderId, solvers[0], destination);
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

    function _resolveLock(
        StandardOrder calldata order,
        bytes calldata sponsorSignature,
        bytes calldata allocatorData,
        bytes32 claimant
    ) internal override {
        BatchClaimComponent[] memory batchClaimComponents;
        {
            uint256 numInputs = order.inputs.length;
            batchClaimComponents = new BatchClaimComponent[](numInputs);
            uint256[2][] calldata maxInputs = order.inputs;
            uint64 fee = governanceFee;
            for (uint256 i; i < numInputs; ++i) {
                uint256[2] calldata input = maxInputs[i];
                uint256 tokenId = input[0];
                uint256 allocatedAmount = input[1];

                Component[] memory components;

                // If the governance fee is set, we need to add a governance fee split.
                uint256 governanceShare = _calcFee(allocatedAmount, fee);
                if (governanceShare != 0) {
                    unchecked {
                        // To reduce the cost associated with the governance fee,
                        // we want to do a 6909 transfer instead of burn and mint.
                        // Note: While this function is called with replaced token, it
                        // replaces the rightmost 20 bytes. So it takes the locktag from TokenId
                        // and places it infront of the current vault owner.
                        uint256 ownerId = IdLib.withReplacedToken(tokenId, owner());
                        components = new Component[](2);
                        // For the user
                        components[0] =
                            Component({ claimant: uint256(claimant), amount: allocatedAmount - governanceShare });
                        // For governance
                        components[1] = Component({ claimant: uint256(ownerId), amount: governanceShare });
                        batchClaimComponents[i] = BatchClaimComponent({
                            id: tokenId, // The token ID of the ERC6909 token to allocate.
                            allocatedAmount: allocatedAmount, // The original allocated amount of ERC6909 tokens.
                            portions: components
                        });
                        continue;
                    }
                }

                components = new Component[](1);
                components[0] = Component({ claimant: uint256(claimant), amount: allocatedAmount });
                batchClaimComponents[i] = BatchClaimComponent({
                    id: tokenId, // The token ID of the ERC6909 token to allocate.
                    allocatedAmount: allocatedAmount, // The original allocated amount of ERC6909 tokens.
                    portions: components
                });
            }
        }

        require(
            COMPACT.batchClaim(
                BatchClaim({
                    allocatorData: allocatorData,
                    sponsorSignature: sponsorSignature,
                    sponsor: order.user,
                    nonce: order.nonce,
                    expires: order.expires,
                    witness: StandardOrderType.witnessHash(order),
                    witnessTypestring: string(StandardOrderType.BATCH_COMPACT_SUB_TYPES),
                    claims: batchClaimComponents
                })
            ) != bytes32(0)
        );
    }
}
