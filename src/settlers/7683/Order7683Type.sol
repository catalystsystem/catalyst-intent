// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription, OutputDescriptionType } from "../types/OutputDescriptionType.sol";

import { GaslessCrossChainOrder, OnchainCrossChainOrder } from "src/interfaces/IERC7683.sol";

struct Input {
    address token;
    uint256 amount;
}

struct CatalystOrderDataWitness {
    address user;
    uint256 nonce;
    address localOracle;
    Input[] inputs;
    OutputDescription[] outputs;
}

/**
 * @notice Helper library for the Catalyst order type.
 * TYPE_PARTIAL: An incomplete type. Is missing a field.
 * TYPE_STUB: Type has no subtypes.
 * TYPE: Is complete including sub-types.
 */
library Order7683Type {
    function orderIdentifier(
        GaslessCrossChainOrder calldata order
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(order));
    }

    function orderIdentifier(
        OnchainCrossChainOrder calldata order
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(order));
    }

    function decode(bytes calldata orderData) internal pure returns(CatalystOrderDataWitness memory) {
        return abi.deocde(orderData, (CatalystOrderDataWitness));
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
