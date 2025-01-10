// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { GaslessCrossChainOrder } from "../interfaces/IERC7683.sol";

struct InputDescription {
    /**
     * @dev The resource lock id of the input
     */
    uint256 tokenId;
    /**
     * @dev The amount of the resource lock that is available.
     */
    uint256 amount;
}

struct OutputDescription {
    /**
     * @dev Contract on the destination that tells whether an order was filled.
     * Format is bytes32() slice of the encoded bytearray from the messaging protocol.
     * If local: bytes32(uint256(uint160(address(localOracle)))).
     */
    bytes32 remoteOracle;
    /**
     * @dev The destination chain for this output.
     */
    uint256 chainId;
    /**
     * @dev The address of the token on the destination chain.
     */
    bytes32 token;
    /**
     * @dev The amount of the token to be sent.
     */
    uint256 amount;
    /**
     * @dev The address to receive the output tokens.
     */
    bytes32 recipient;
    /**
     * @dev Additonal data that will be used to execute a call on the remote chain.
     * Is called on recipient.
     */
    bytes remoteCall;
}

struct CatalystOrderData {
    //- Oracle Context -//
    address localOracle;
    address collateralToken;
    uint256 collateralAmount;
    uint32 proofDeadline;
    uint32 challengeDeadline;
    InputDescription[] inputs;
    OutputDescription[] outputs;
}

/**
 * @notice Helper library for the Catalyst order type.
 * TYPE_PARTIAL: An incomplete type. Is missing a field.
 * TYPE_STUB: Type has no subtypes. 
 * TYPE: Is complete including sub-types.
 */
library CatalystOrderType {
    bytes constant CATALYST_ORDER_DATA_TYPE_STUB = abi.encodePacked(
        "CatalystOrderData("
        "address localOracle,"
        "address collateralToken,"
        "uint256 collateralAmount,"
        "uint32 proofDeadline,"
        "uint32 challengeDeadline,"
        "InputDescription[] inputs,"
        "OutputDescription[] outputs"
        ")"
    );

    bytes constant CATALYST_ORDER_DATA_TYPE = abi.encodePacked(
        CATALYST_ORDER_DATA_TYPE_STUB,
        INPUT_DESCRIPTION_TYPE_STUB,
        OUTPUT_DESCRIPTION_TYPE_STUB
    );

    bytes32 constant CATALYST_ORDER_DATA_TYPE_HASH = keccak256(CATALYST_ORDER_DATA_TYPE);

    bytes constant GASSLESS_CROSS_CHAIN_ORDER_TYPE_PARTIAL = abi.encodePacked(
        "CrossChainOrder("
        "address originSettler,"
        "address user,"
        "uint256 nonce,"
        "uint256 originChainId,"
        "uint32 openDeadline,"
        "uint32 fillDeadline," // TODO: What to do about the fillDeadline
	    "bytes32 orderDataType"  // TODO: Should this be here?
    );

    bytes constant GASSLESS_CROSS_CHAIN_ORDER_TYPE_STUB = abi.encodePacked(
        GASSLESS_CROSS_CHAIN_ORDER_TYPE_PARTIAL, "CatalystOrderData orderData)"
    );

    bytes constant GASSLESS_CROSS_CHAIN_ORDER_TYPE = abi.encodePacked(
        GASSLESS_CROSS_CHAIN_ORDER_TYPE_STUB,
        CATALYST_ORDER_DATA_TYPE_STUB,
        INPUT_DESCRIPTION_TYPE_STUB,
        OUTPUT_DESCRIPTION_TYPE_STUB
    );

    bytes32 constant GASSLESS_CROSS_CHAIN_ORDER_TYPE_HASH = keccak256(GASSLESS_CROSS_CHAIN_ORDER_TYPE);

    bytes constant BATCH_COMPACT_TYPE_PARTIAL = abi.encodePacked(
        "BatchCompact("
        "address arbiter"
        "address sponsor"
        "uint256 nonce"
        "uint256 expires"
        "uint256[2][] idsAndAmounts"
    );

    bytes constant BATCH_COMPACT_TYPE_STUB = abi.encodePacked(
        BATCH_COMPACT_TYPE_PARTIAL,
        "CrossChainOrder witness)"
    );

    bytes constant BATCH_COMPACT_TYPE = abi.encodePacked(
        BATCH_COMPACT_TYPE_STUB,
        CATALYST_ORDER_DATA_TYPE_STUB,
        GASSLESS_CROSS_CHAIN_ORDER_TYPE_STUB,
        INPUT_DESCRIPTION_TYPE_STUB,
        OUTPUT_DESCRIPTION_TYPE_STUB
    );

    bytes32 constant BATCH_COMPACT_TYPE_HASH = keccak256(BATCH_COMPACT_TYPE);

    function hashOrderDataM(
        CatalystOrderData memory orderData
    ) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    CATALYST_ORDER_DATA_TYPE_HASH,
                    orderData.localOracle,
                    orderData.collateralToken,
                    orderData.collateralAmount,
                    orderData.proofDeadline,
                    orderData.challengeDeadline,
                    hashInputs(orderData.inputs),
                    hashOutputs(orderData.outputs)
                )
            )
        );
    }

    function orderHash(
        GaslessCrossChainOrder calldata order,
        CatalystOrderData memory orderData
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                GASSLESS_CROSS_CHAIN_ORDER_TYPE_HASH,
                order.originSettler,
                order.user,
                order.nonce,
                order.originChainId,
                order.openDeadline,
                order.fillDeadline,
                order.orderDataType,
                hashOrderDataM(orderData)
            )
        );
    }

    function compactHash(
        address arbiter,
        uint256 sponsor,
        uint256 nonce,
        uint256 expires,
        GaslessCrossChainOrder calldata order,
        CatalystOrderData memory orderData
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                BATCH_COMPACT_TYPE_HASH,
                arbiter,
                sponsor,
                nonce,
                expires,
                hashIdsAndAmounts(orderData.inputs),
                orderHash(order, orderData)
            )
        );
    }

    function hashIdsAndAmounts(
        InputDescription[] memory inputs
    ) internal pure returns (bytes32) {
        uint256 numInputs = inputs.length;

        bytes memory encodedIdsAndAmounts;
        for (uint256 i; i < numInputs; ++i) {
            InputDescription memory input = inputs[i];
            encodedIdsAndAmounts = abi.encodePacked(encodedIdsAndAmounts, input.tokenId, input.amount);
        }

        return keccak256(encodedIdsAndAmounts);
    }

    //--- Inputs & Outputs Types ---//

    bytes constant INPUT_DESCRIPTION_TYPE_STUB = abi.encodePacked(
        "InputDescription(",
        "uint256 tokenId,",
        "uint256 amount",
        ")"
    );

    bytes32 constant INPUT_DESCRIPTION_TYPE_HASH = keccak256(INPUT_DESCRIPTION_TYPE_STUB);

    bytes constant OUTPUT_DESCRIPTION_TYPE_STUB = abi.encodePacked(
        "OutputDescription("
        "bytes32 remoteOracle,"
        "uint256 chainId,"
        "bytes32 token,"
        "uint256 amount,"
        "bytes32 recipient,"
        "bytes remoteCall,"
        ")"
    );

    bytes32 constant OUTPUT_DESCRIPTION_TYPE_HASH = keccak256(INPUT_DESCRIPTION_TYPE_STUB);

    function hashInput(InputDescription memory input) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                INPUT_DESCRIPTION_TYPE_HASH,
                input.tokenId,
                input.amount
            )
        );
    }

    function hashOutput(OutputDescription memory output) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OUTPUT_DESCRIPTION_TYPE_HASH,
                output.remoteOracle,
                output.chainId,
                output.token,
                output.amount,
                output.recipient,
                keccak256(output.remoteCall)
            )
        );
    }

    function hashInputs(InputDescription[] memory inputs) internal pure returns (bytes32) {
        unchecked {
            bytes memory currentHash = new bytes(32 * inputs.length);

            for (uint256 i = 0; i < inputs.length; ++i) {
                bytes32 inputHash = hashInput(inputs[i]);
                assembly {
                    mstore(add(add(currentHash, 0x20), mul(i, 0x20)), inputHash)
                }
            }
            return keccak256(currentHash);
        }
    }

    function hashOutputs(
        OutputDescription[] memory outputs
    ) internal pure returns (bytes32) {
        unchecked {
            bytes memory currentHash = new bytes(32 * outputs.length);

            for (uint256 i = 0; i < outputs.length; ++i) {
                bytes32 outputHash = hashOutput(outputs[i]);
                assembly {
                    mstore(add(add(currentHash, 0x20), mul(i, 0x20)), outputHash)
                }
            }
            return keccak256(currentHash);
        }
    }

}
