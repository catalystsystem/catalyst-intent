// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription, OutputDescriptionType } from "../types/OutputDescriptionType.sol";

struct CatalystCompactOrder {
    address user;
    uint256 nonce;
    uint256 originChainId;
    uint32 expires;
    uint32 fillDeadline;
    address localOracle;
    uint256[2][] inputs;
    OutputDescription[] outputs;
}

/**
 * @notice This is the signed Catalyst witness structure. This allows us to more easily collect the order hash.
 * Notice that this is different to both the order data and the ERC7683 order.
 */
struct CatalystWitness {
    uint32 fillDeadline;
    address localOracle;
    OutputDescription[] outputs;
}

/**
 * @notice Helper library for the Catalyst order type.
 * TYPE_PARTIAL: An incomplete type. Is missing a field.
 * TYPE_STUB: Type has no subtypes.
 * TYPE: Is complete including sub-types.
 */
library TheCompactOrderType {
    function orderIdentifier(
        CatalystCompactOrder calldata order
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(block.chainid, address(this), order.user, order.nonce, order.fillDeadline, order.localOracle, order.inputs, abi.encode(order.outputs)));
    }

    bytes constant CATALYST_WITNESS_TYPE_STUB = abi.encodePacked("CatalystWitness(" "uint32 fillDeadline," "address localOracle," "OutputDescription[] outputs" ")");

    bytes constant CATALYST_WITNESS_TYPE = abi.encodePacked(CATALYST_WITNESS_TYPE_STUB, OutputDescriptionType.OUTPUT_DESCRIPTION_TYPE_STUB);

    bytes32 constant CATALYST_WITNESS_TYPE_HASH = keccak256(CATALYST_WITNESS_TYPE);

    bytes constant BATCH_COMPACT_TYPE_PARTIAL = abi.encodePacked("BatchCompact(" "address arbiter," "address sponsor," "uint256 nonce," "uint256 expires," "uint256[2][] idsAndAmounts,");

    bytes constant BATCH_SUB_TYPES = abi.encodePacked("CatalystWitness witness)", CATALYST_WITNESS_TYPE_STUB, OutputDescriptionType.OUTPUT_DESCRIPTION_TYPE_STUB);

    bytes constant BATCH_COMPACT_TYPE = abi.encodePacked(BATCH_COMPACT_TYPE_PARTIAL, BATCH_SUB_TYPES);

    bytes32 constant BATCH_COMPACT_TYPE_HASH = keccak256(BATCH_COMPACT_TYPE);

    function orderHash(
        CatalystCompactOrder calldata order
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(CATALYST_WITNESS_TYPE_HASH, order.fillDeadline, order.localOracle, OutputDescriptionType.hashOutputs(order.outputs)));
    }

    function compactHash(address arbiter, address sponsor, uint256 nonce, uint256 expires, CatalystCompactOrder calldata order) internal pure returns (bytes32) {
        return keccak256(abi.encode(BATCH_COMPACT_TYPE_HASH, arbiter, sponsor, nonce, expires, hashIdsAndAmounts(order.inputs), orderHash(order)));
    }

    function hashIdsAndAmounts(
        uint256[2][] memory inputs
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(inputs));
    }
}
