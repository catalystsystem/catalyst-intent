// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CrossChainOrderType } from "./CrossChainOrderType.sol";

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
     * @dev Sets the order type. Is needed to decode fulfillmentContext and identify the order type
     */
    uint8 orderType;
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
     * @dev The destination chain for this output.
     */
    uint256 chainId;
    /**
     * @dev Contract on the destination that tells whether an order was filled.
     * Format is bytes32() slice of the encoded bytearray from the messaging protocol.
     * If local: bytes32(uint256(uint160(address(localOracle)))).
     */
    bytes32 remoteOracle;
    /**
     * @dev Additonal data that will be used to execute a call on the remote chain.
     * Is called on recipient.
     */
    bytes remoteCall;
    /**
     * @dev Additional data for the order that impacts order data availability. 
     */
    bytes fulfillmentContext;
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
 */
library CrossChainOrderType {
    bytes constant GASSLESS_CROSS_CHAIN_ORDER_TYPE_NO_DATA_STUB = abi.encodePacked(
        "CrossChainOrder(",
        "address originSettler,",
        "address user,",
        "uint256 nonce,",
        "uint256 originChainId,",
        "uint32 openDeadline,",
        "uint32 fillDeadline,", // TODO: What to do about the fillDeadline
	    "bytes32 orderDataType"
    );

    //--- Token Types ---//

    bytes constant INPUT_TYPE = abi.encodePacked(
        "Input(",
        "uint256 tokenId,",
        "uint256 amount",
        ")"
    );

    bytes constant OUTPUT_TYPE = abi.encodePacked(
        "OutputDescription(",
        "bytes32 token,",
        "uint256 amount,",
        "bytes32 recipient,",
        "uint256 chainId,",
        "bytes32 remoteOracle,",
        "bytes remoteCall,",
        "uint8 orderType,",
        "bytes fulfillmentContext",
        ")"
    );

    string constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";

    function hashInput(InputDescription memory input) internal pure returns (bytes32) {
        return keccak256(abi.encode(keccak256(INPUT_TYPE), input.token, input.amount));
    }

    function hashOutput(OutputDescription memory output) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(OUTPUT_TYPE_STUB),
                output.token,
                output.amount,
                output.recipient,
                output.chainId,
                keccak256(output.remoteCall),
                output.remoteOracle,
                output.orderType,
                keccak256(output.fulfillmentContext)
            )
        );
    }

    function hashInputs(Input[] memory inputs) internal pure returns (bytes32) {
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

    //--- Order Types ---//

    bytes constant CATALYST_ORDER_DATA_TYPE = abi.encodePacked(
        LIMIT_ORDER_DATA_TYPE_ONLY, INPUT_TYPE, OUTPUT_TYPE
    );

    bytes constant CATALYST_ORDER_DATA_TYPE_ONLY = abi.encodePacked(
        "CatalystOrderData(",
        "address localOracle,",
        "address collateralToken,",
        "uint256 collateralAmount,",
        "uint32 proofDeadline,",
        "uint32 challengeDeadline,",
        "InputDescription[] inputs,",
        "OutputDescription[] outputs",
        ")"
    );

    bytes constant GASSLESS_CROSS_CHAIN_ORDER_TYPE = abi.encodePacked(
        GASSLESS_CROSS_CHAIN_ORDER_TYPE_NO_DATA_STUB, "CatalystOrderData orderData", ")"
    );

    string constant CATALYST_ORDER_WITNESS_STRING_TYPE = string(
        abi.encodePacked(
            "CrossChainOrder witness)",
            LIMIT_ORDER_DATA_TYPE_ONLY,
            LIMIT_CROSS_CHAIN_ORDER_TYPE,
            INPUT_TYPE_STUB,
            OUTPUT_TYPE_STUB
            // TODO:
        )
    );

    bytes32 constant CATALYST_ORDER_DATA_TYPE_HASH = keccak256(CATALYST_ORDER_DATA_TYPE);

    function decodeOrderData(
        bytes calldata orderBytes
    ) internal pure returns (CatalystLimitOrderData memory limitData) {
        return limitData = abi.decode(orderBytes, (CatalystLimitOrderData));
    }

    function hashOrderDataM(
        CatalystLimitOrderData memory orderData
    ) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    LIMIT_ORDER_DATA_TYPE_HASH,
                    orderData.proofDeadline,
                    orderData.challengeDeadline,
                    orderData.collateralToken,
                    orderData.fillerCollateralAmount,
                    orderData.challengerCollateralAmount,
                    orderData.localOracle
                ),
                abi.encode(
                    CrossChainOrderType.hashInputs(orderData.inputs), CrossChainOrderType.hashOutputs(orderData.outputs)
                )
            )
        );
    }

    function crossOrderHash(
        CrossChainOrder calldata order,
        CatalystLimitOrderData memory limitOrderData
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(abi.encodePacked(LIMIT_CROSS_CHAIN_ORDER_TYPE, LIMIT_ORDER_DATA_TYPE)),
                order.settlementContract,
                order.swapper,
                order.nonce,
                order.originChainId,
                order.initiateDeadline,
                order.fillDeadline,
                hashOrderDataM(limitOrderData)
            )
        );
    }
}
