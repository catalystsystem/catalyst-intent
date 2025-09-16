// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";
import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";

import { MandateOutput, MandateOutputType } from "OIF/src/input/types/MandateOutputType.sol";
import { StandardOrder, StandardOrderType } from "OIF/src/input/types/StandardOrderType.sol";
import { LibAddress } from "OIF/src/libs/LibAddress.sol";

/**
 * @notice Intent Registration library. Aids with registration of intents onbehalf of someone else for The Compact.
 * @dev If the library is not used for registering intents, it contains helpers for validation and intent hashes.
 */
library RegisterIntentLib {
    using LibAddress for uint256;

    error DeadlinePassed();
    error WrongChain(uint256 expected, uint256 provided);

    bytes32 constant STANDARD_ORDER_BATCH_COMPACT_TYPE_HASH = keccak256(
        bytes(
            "BatchCompact(address arbiter,address sponsor,uint256 nonce,uint256 expires,Lock[] commitments,Mandate mandate)Lock(bytes12 lockTag,address token,uint256 amount)Mandate(uint32 fillDeadline,address inputOracle,MandateOutput[] outputs)MandateOutput(bytes32 oracle,bytes32 settler,uint256 chainId,bytes32 token,uint256 amount,bytes32 recipient,bytes call,bytes context)"
        )
    );

    /**
     * @notice Hashes a MandateOutput struct.
     * @param output The MandateOutput struct to hash.
     * @return The hash of the MandateOutput struct.
     */
    function hashOutput(
        MandateOutput memory output
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                MandateOutputType.MANDATE_OUTPUT_TYPE_HASH,
                output.oracle,
                output.settler,
                output.chainId,
                output.token,
                output.amount,
                output.recipient,
                keccak256(output.call),
                keccak256(output.context)
            )
        );
    }

    /**
     * @notice Hashes a list of MandateOutput structs.
     * @param outputs The list of MandateOutput structs to hash.
     * @return The hash of the list of MandateOutput structs.
     */
    function hashOutputs(
        MandateOutput[] memory outputs
    ) internal pure returns (bytes32) {
        unchecked {
            bytes memory currentHash = new bytes(32 * outputs.length);
            uint256 p;
            assembly ("memory-safe") {
                p := add(currentHash, 0x20)
            }
            for (uint256 i = 0; i < outputs.length; ++i) {
                bytes32 outputHash = hashOutput(outputs[i]);
                assembly ("memory-safe") {
                    mstore(add(p, mul(i, 0x20)), outputHash)
                }
            }
            return keccak256(currentHash);
        }
    }

    // Copy from OIF implementation with elements in memory for usage inside other contracts constructing the
    // StandardOrder.
    function witnessHash(
        StandardOrder memory order
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                StandardOrderType.CATALYST_WITNESS_TYPE_HASH,
                order.fillDeadline,
                order.inputOracle,
                hashOutputs(order.outputs)
            )
        );
    }

    function getLocksHash(
        uint256[2][] calldata idsAndAmounts
    ) public pure returns (bytes32) {
        unchecked {
            uint256 numIdsAndAmounts = idsAndAmounts.length;
            bytes memory currentHash = new bytes(32 * numIdsAndAmounts);
            for (uint256 i; i < numIdsAndAmounts; ++i) {
                uint256[2] calldata idsAndAmount = idsAndAmounts[i];
                bytes32 lockHash = keccak256(
                    abi.encode(
                        keccak256(bytes("Lock(bytes12 lockTag,address token,uint256 amount)")),
                        bytes12(bytes32(idsAndAmount[0])),
                        address(uint160(idsAndAmount[0])),
                        idsAndAmount[1]
                    )
                );
                assembly ("memory-safe") {
                    mstore(add(add(currentHash, 0x20), mul(i, 0x20)), lockHash)
                }
            }

            return keccak256(currentHash);
        }
    }

    function compactClaimHash(address settler, StandardOrder calldata order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                STANDARD_ORDER_BATCH_COMPACT_TYPE_HASH,
                settler,
                order.user,
                order.nonce,
                order.expires,
                getLocksHash(order.inputs),
                StandardOrderType.witnessHash(order)
            )
        );
    }

    function _validateChain(
        uint256 originChainId
    ) internal view {
        // Check that this is the right originChain
        if (block.chainid != originChainId) revert WrongChain(block.chainid, originChainId);
    }

    function _validateExpiry(uint32 fillDeadline, uint32 expires) internal view {
        // Check if the fill deadline has been passed
        if (block.timestamp > fillDeadline) revert DeadlinePassed();
        // Check if expiry has been passed
        if (block.timestamp > expires) revert DeadlinePassed();
    }

    /**
     * @notice Deposits and registers the intent associated with an OIF StandardOrder.
     * @param setApprovals Whether or not to set approvals for the intents inputs. Set as a constant such that the
     * Solidity function specialiser either deletes or inlines the loop.
     */
    function depositAndRegisterIntentFor(
        address COMPACT,
        address arbiter,
        StandardOrder memory order,
        bool setApprovals
    ) internal returns (bytes32 claimHash) {
        _validateChain(order.originChainId);
        _validateExpiry(order.fillDeadline, order.expires);

        uint256[2][] memory idsAndAmounts = order.inputs;
        if (setApprovals) {
            uint256 numInputs = idsAndAmounts.length;
            for (uint256 i; i < numInputs; ++i) {
                uint256[2] memory idAndAmount = idsAndAmounts[i];
                SafeTransferLib.safeApproveWithRetry(idAndAmount[0].fromIdentifier(), address(COMPACT), idAndAmount[1]);
            }
        }

        (claimHash,) = TheCompact(COMPACT).batchDepositAndRegisterFor(
            order.user,
            idsAndAmounts,
            arbiter,
            order.nonce,
            order.expires,
            STANDARD_ORDER_BATCH_COMPACT_TYPE_HASH,
            witnessHash(order)
        );
    }
}
