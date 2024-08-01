// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output } from "../interfaces/ISettlementContract.sol";

library CrossChainOrderType {
    bytes constant CROSS_CHAIN_ORDER_TYPE_STUB = abi.encodePacked(
        "CrossChainOrder(",
        "address settlementContract,",
        "address swapper,",
        "uint256 nonce,",
        "uint32 originChainId,",
        "uint32 initiateDeadline,",
        "uint32 fillDeadline,"
    );

    bytes constant INPUT_TYPE_STUB = abi.encodePacked("Input(", "address token,", "uint256 amount", ")");

    bytes constant OUTPUT_TYPE_STUB =
        abi.encodePacked("Output(", "bytes32 token,", "uint256 amount,", "bytes32 recipient,", "uint32 chainId", ")");

    string constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";

    function crossOrderType(bytes memory orderData, bytes memory orderType) internal pure returns (bytes memory) {
        return abi.encodePacked(CROSS_CHAIN_ORDER_TYPE_STUB, orderData, ")", orderType);
    }

    function hashInput(Input memory input) internal pure returns (bytes32) {
        return keccak256(abi.encode(INPUT_TYPE_STUB, input.token, input.amount));
    }

    function hashOutput(Output memory output) internal pure returns (bytes32) {
        return keccak256(abi.encode(OUTPUT_TYPE_STUB, output.token, output.amount, output.recipient, output.chainId));
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

    function hashOutputs(Output[] memory outputs) internal pure returns (bytes32) {
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

    function hash(
        CrossChainOrder calldata order,
        bytes32 orderTypeHash,
        bytes32 orderDataHash
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                orderTypeHash,
                order.settlementContract,
                order.swapper,
                order.nonce,
                order.originChainId,
                order.initiateDeadline,
                order.fillDeadline,
                orderDataHash
            )
        );
    }

    function permit2WitnessType(bytes memory orderType)
        internal
        pure
        returns (string memory permit2WitnessTypeString)
    {
        permit2WitnessTypeString =
            string(abi.encodePacked("CrossChainOrder witness)", orderType, TOKEN_PERMISSIONS_TYPE));
    }
}
