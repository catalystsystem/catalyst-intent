// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "src/libs/OutputEncodingLib.sol";

/**
 * @notice Signed struct
 */
struct SignedOutput {
    bytes32 winner;

    bytes32 remoteOracle;
    bytes32 remoteFiller;
    uint256 chainId;
    bytes32 token;
    uint256 amount;
    /** @dev Ammended amount to the original order. */
    uint256 trueAmount;
    bytes32 recipient;
    bytes remoteCall;
    bytes fulfillmentContext;
}

/**
 * @notice Helper library for the Signed Output type.
 * TYPE_PARTIAL: An incomplete type. Is missing a field.
 * TYPE_STUB: Type has no subtypes.
 * TYPE: Is complete including sub-types.
 */
library SignedOutputType {
    bytes constant SIGNED_OUTPUT_TYPE_STUB = abi.encodePacked(
        "OutputDescription(" "bytes32 winner," "bytes32 remoteOracle," "bytes32 remoteFiller," "uint256 chainId," "bytes32 token," "uint256 amount," "uint256 trueAmount," "bytes32 recipient," "bytes remoteCall," "bytes fulfillmentContext" ")"
    );

    bytes32 constant SIGNED_OUTPUT_TYPE_HASH = keccak256(SIGNED_OUTPUT_TYPE_STUB);

    function hashSignedOutput(OutputDescription calldata output, bytes32 winner, uint256 trueAmount) internal pure returns (bytes32) {
        return keccak256(abi.encode(
                SIGNED_OUTPUT_TYPE_HASH,
                winner,
                output.remoteOracle,
                output.remoteFiller,
                output.chainId,
                output.token,
                output.amount,
                trueAmount,
                output.recipient,
                keccak256(output.remoteCall),
                keccak256(output.fulfillmentContext)
            )
        );
    }
}
