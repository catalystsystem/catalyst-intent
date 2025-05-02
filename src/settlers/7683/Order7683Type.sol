// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription, OutputDescriptionType } from "../types/OutputDescriptionType.sol";
import { GaslessCrossChainOrder, OnchainCrossChainOrder } from "src/interfaces/IERC7683.sol";

/** @dev The ERC7683 order uses the same order type as TheCompact orders. However, we have a different witness. */
import { CatalystCompactOrder } from "../compact/TheCompactOrderType.sol";

/** @notice The signed witness / mandate used for the permit2 transaction. */
struct MandateERC7683 {
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
    ) internal pure returns (CatalystCompactOrder memory compactOrder) {
        MandateERC7683 memory orderData = abi.decode(gaslessOrder.orderData, (MandateERC7683));
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
        MandateERC7683 memory orderData = abi.decode(onchainOrder.orderData, (MandateERC7683));
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

    bytes constant CATALYST_WITNESS_TYPE_STUB = abi.encodePacked("MandateERC7683(address user,uint256 nonce,address localOracle,uint256[2][] inputs,MandateOutput[] outputs)");

    bytes constant CATALYST_WITNESS_TYPE = abi.encodePacked(CATALYST_WITNESS_TYPE_STUB, OutputDescriptionType.MANDATE_OUTPUT_TYPE_STUB);

    bytes constant ERC7683_GASLESS_CROSS_CHAIN_ORDER_PARTIAL = abi.encodePacked(
        "GaslessCrossChainOrder(address originSettler,address user,uint256 nonce,uint256 originChainId,uint32 openDeadline,uint32 fillDeadline,bytes32 orderDataType"
    );

    bytes constant ERC7683_GASLESS_CROSS_CHAIN_ORDER_STUB = abi.encodePacked(
        ERC7683_GASLESS_CROSS_CHAIN_ORDER_PARTIAL, ",MandateERC7683 orderData)"
    );

    bytes constant ERC7683_GASLESS_CROSS_CHAIN_ORDER = abi.encodePacked(
        ERC7683_GASLESS_CROSS_CHAIN_ORDER_STUB, CATALYST_WITNESS_TYPE
    );

    bytes32 constant ERC7683_GASLESS_CROSS_CHAIN_ORDER_TYPE_HASH = keccak256(ERC7683_GASLESS_CROSS_CHAIN_ORDER);

    function witnessHash(
        GaslessCrossChainOrder calldata order,
        CatalystCompactOrder memory compactOrder
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ERC7683_GASLESS_CROSS_CHAIN_ORDER_TYPE_HASH,
                order.originSettler,
                order.user,
                order.nonce,
                order.originChainId,
                order.openDeadline,
                order.fillDeadline,
                order.orderDataType,
                orderDataHash(compactOrder)
            )
        );
    }

    function orderDataHash(
        CatalystCompactOrder memory order
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CATALYST_WITNESS_TYPE,
                order.expires,
                order.user,
                order.nonce,
                order.localOracle,
                order.inputs,
                order.outputs
            )
        );
    }


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
