// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "src/libs/OutputEncodingLib.sol";

/**
 * @notice Helper library for the Output description order type.
 * TYPE_PARTIAL: An incomplete type. Is missing a field.'
 * TYPE_STUB: Type has no subtypes.
 * TYPE: Is complete including sub-types.
 */
library OutputDescriptionType {
    //--- Inputs & Outputs Types ---//

    bytes constant OUTPUT_DESCRIPTION_TYPE_STUB =
        abi.encodePacked("OutputDescription(" "bytes32 remoteOracle," "uint256 chainId," "bytes32 token," "uint256 amount," "bytes32 recipient," "bytes remoteCall," "bytes fulfillmentContext" ")");

    bytes32 constant OUTPUT_DESCRIPTION_TYPE_HASH = keccak256(OUTPUT_DESCRIPTION_TYPE_STUB);

    function hashOutput(
        OutputDescription memory output
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(OUTPUT_DESCRIPTION_TYPE_HASH, output.remoteOracle, output.chainId, output.token, output.amount, output.recipient, keccak256(output.remoteCall), keccak256(output.fulfillmentContext))
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
