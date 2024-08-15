// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input } from "../../interfaces/ISettlementContract.sol";


import { OutputDescription } from "../../interfaces/Structs.sol";


library CrossChainOrderType {
    bytes constant INPUT_TYPE_STUB = abi.encodePacked("Input(", "address token,", "uint256 amount", ")");

    bytes constant OUTPUT_TYPE_STUB =
        abi.encodePacked("Output(", "bytes32 token,", "uint256 amount,", "bytes32 recipient,", "uint32 chainId", ")");

    string constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";

    function hashInput(Input memory input) internal pure returns (bytes32) {
        return keccak256(abi.encode(keccak256(INPUT_TYPE_STUB), input.token, input.amount));
    }

    // TODO: Permit2 description of output
    function hashOutput(OutputDescription memory output) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(keccak256(OUTPUT_TYPE_STUB), output.token, output.amount, output.recipient, output.chainId)
        );
    }

    function hashInputs(Input[] memory inputs) internal pure returns (bytes32) {
        unchecked {
            bytes memory currentHash = new bytes(32 * inputs.length);

            for (uint256 i = 0; i < inputs.length; i++) {
                bytes32 inputHash = hashInput(inputs[i]);
                assembly {
                    mstore(add(add(currentHash, 0x20), mul(i, 0x20)), inputHash)
                }
            }
            return keccak256(currentHash);
        }
    }

    function hashOutputs(OutputDescription[] memory outputs) internal pure returns (bytes32) {
        unchecked {
            bytes memory currentHash = new bytes(32 * outputs.length);

            for (uint256 i = 0; i < outputs.length; i++) {
                bytes32 outputHash = hashOutput(outputs[i]);
                assembly {
                    mstore(add(add(currentHash, 0x20), mul(i, 0x20)), outputHash)
                }
            }
            return keccak256(currentHash);
        }
    }
}
