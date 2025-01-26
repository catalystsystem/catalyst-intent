// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

struct OutputDescription {
    /**
     * @dev Contract on the destination that tells whether an order was filled.
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
     * @dev Additional data that will be used to execute a call on the remote chain.
     * Is called on recipient.
     */
    bytes remoteCall;

    bytes fulfillmentContext;
}

struct CatalystOrderData {
    //- Oracle Context -//
    address localOracle;
    address collateralToken;
    uint256 collateralAmount;
    uint32 proofDeadline;
    uint32 challengeDeadline;
    uint256[2][] inputs; // TODO: expose the difference between the signed order and the delivered one.
    OutputDescription[] outputs;
}

/**
 * @notice Helper library for the Catalyst order type.
 * TYPE_PARTIAL: An incomplete type. Is missing a field.
 * TYPE_STUB: Type has no subtypes. 
 * TYPE: Is complete including sub-types.
 */
library CatalystOrderType {
    //--- Inputs & Outputs Types ---//

    bytes constant OUTPUT_DESCRIPTION_TYPE_STUB = abi.encodePacked(
        "OutputDescription("
        "bytes32 remoteOracle,"
        "uint256 chainId,"
        "bytes32 token,"
        "uint256 amount,"
        "bytes32 recipient,"
        "bytes remoteCall,"
        "bytes fulfillmentContext"
        ")"
    );

    bytes32 constant OUTPUT_DESCRIPTION_TYPE_HASH = keccak256(OUTPUT_DESCRIPTION_TYPE_STUB);

    function hashOutput(OutputDescription memory output) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OUTPUT_DESCRIPTION_TYPE_HASH,
                output.remoteOracle,
                output.chainId,
                output.token,
                output.amount,
                output.recipient,
                keccak256(output.remoteCall),
                keccak256(output.fulfillmentContext)
            )
        );
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
