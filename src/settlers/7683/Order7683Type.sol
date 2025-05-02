// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription, OutputDescriptionType } from "../types/OutputDescriptionType.sol";
import { GaslessCrossChainOrder, OnchainCrossChainOrder } from "src/interfaces/IERC7683.sol";

/** @dev The ERC7683 order uses the same order type as TheCompact orders. However, we have a different witness. */
import { CatalystCompactOrder } from "../compact/TheCompactOrderType.sol";

/** @notice The signed witness / mandate used for the permit2 transaction. */
struct MandatePermit2 {
    uint32 expiry;
    address user;
    uint256 nonce;
    address localOracle;
    uint256[2][] inputs; // [address, amount]
    OutputDescription[] outputs;
}

/**
 * @notice Helper library for the Catalyst order type.
 * TYPE_PARTIAL: An incomplete type. Is missing a field.
 * TYPE_STUB: Type has no subtypes.
 * TYPE: Is complete including sub-types.
 */
library Order7683Type {
    /**
     * @notice Get an order identifier for an entire order description.
     * @dev Is copied from TheCompactOrderType.
     */
    function orderIdentifier(
        CatalystCompactOrder calldata order
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                block.chainid,
                address(this),
                order.user,
                order.nonce,
                order.fillDeadline,
                order.localOracle,
                order.inputs,
                abi.encode(order.outputs)
            )
        );
    }

    /**
     * @notice Get an order identifier for an entire order description.
     * @dev Is copied from TheCompactOrderType.
     */
    function orderIdentifierMemory(
        CatalystCompactOrder memory order
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                block.chainid,
                address(this),
                order.user,
                order.nonce,
                order.fillDeadline,
                order.localOracle,
                order.inputs,
                abi.encode(order.outputs)
            )
        );
    }


    function convertToCompactOrder(
        GaslessCrossChainOrder calldata gaslessOrder
    ) internal pure returns (CatalystCompactOrder memory compactOrder, MandatePermit2 memory orderData) {
        orderData = abi.decode(gaslessOrder.orderData, (MandatePermit2));
        compactOrder = CatalystCompactOrder({
            user: gaslessOrder.user,
            nonce: gaslessOrder.nonce,
            originChainId: gaslessOrder.originChainId,
            expires: orderData.expiry,
            fillDeadline: gaslessOrder.fillDeadline,
            localOracle: orderData.localOracle,
            inputs: orderData.inputs,
            outputs: orderData.outputs
        });
    }

    function convertToCompactOrder(
        address user,
        OnchainCrossChainOrder calldata onchainOrder
    ) internal view returns (CatalystCompactOrder memory compactOrder) {
        MandatePermit2 memory orderData = abi.decode(onchainOrder.orderData, (MandatePermit2));
        compactOrder = CatalystCompactOrder({
            user: user,
            nonce: 0,
            originChainId: block.chainid,
            expires: orderData.expiry,
            fillDeadline: onchainOrder.fillDeadline,
            localOracle: orderData.localOracle,
            inputs: orderData.inputs,
            outputs: orderData.outputs
        });
    }

    function decode(bytes calldata orderData) internal pure returns(MandatePermit2 memory) {
        return abi.decode(orderData, (MandatePermit2));
    }

    bytes constant CATALYST_WITNESS_TYPE_STUB = abi.encodePacked("MandatePermit2(address user,uint256 nonce,address localOracle,uint256[2][] inputs,OutputDescription[] outputs)");

    bytes constant CATALYST_WITNESS_TYPE = abi.encodePacked(CATALYST_WITNESS_TYPE_STUB, OutputDescriptionType.MANDATE_OUTPUT_TYPE_STUB);

    bytes32 constant CATALYST_WITNESS_TYPE_HASH = keccak256(CATALYST_WITNESS_TYPE);


    function toIdsAndAmountsHashMemory(
        uint256[2][] memory inputs
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(inputs));
    }

    /**
     * @notice Internal pure function for deriving the hash of ids and amounts provided.
     
     * @param idsAndAmounts      An array of ids and amounts.
     * @return idsAndAmountsHash The hash of the ids and amounts.
     * @dev From TheCompact src/lib/HashLib.sol
     * This function expects that the calldata of idsAndAmounts will have bounds
     * checked elsewhere; using it without this check occurring elsewhere can result in
     * erroneous hash values.
     */
    function toIdsAndAmountsHash(uint256[2][] calldata idsAndAmounts)
        internal
        pure
        returns (bytes32 idsAndAmountsHash)
    {
        assembly ("memory-safe") {
            // Retrieve the free memory pointer; memory will be left dirtied.
            let ptr := mload(0x40)

            // Get the total length of the calldata slice.
            // Each element of the array consists of 2 words.
            let len := mul(idsAndAmounts.length, 0x40)

            // Copy calldata into memory at the free memory pointer.
            calldatacopy(ptr, idsAndAmounts.offset, len)

            // Compute the hash of the calldata that has been copied into memory.
            idsAndAmountsHash := keccak256(ptr, len)
        }
    }
}
