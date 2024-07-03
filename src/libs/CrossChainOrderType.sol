// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder, Input, Output } from "../interfaces/ISettlementContract.sol";

library CrossChainOrderType {
    bytes constant CROSS_CHAIN_ORDER_TYPE_STUB = abi.encodePacked(
        "CrossChainOrder(",
        "address settlerContract,",
        "address swapper,",
        "uint256 nonce,",
        "uint32 originChainId,",
        "uint32 initiateDeadline,",
        "uint32 fillDeadline,"
    );

    bytes constant INPUT_TYPE_STUB = abi.encodePacked("Input(", "address token,", "uint256 amount", ")");

    bytes constant OUTPUT_TYPE_STUB =
        abi.encodePacked("Output(", "bytes32 token,", "uint256 amount,", "bytes32 recipient,", "uint32 chainId,", ")");

    string constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";

    function crossOrderType(bytes memory orderData, bytes memory orderType) internal pure returns (bytes memory) {
        return abi.encodePacked(CROSS_CHAIN_ORDER_TYPE_STUB, orderData, ")", orderType);
    }

    function crossOrderHash(bytes memory orderData, bytes memory orderType) internal pure returns (bytes32) {
        return keccak256(crossOrderType(orderData, orderType));
    }

    function hashInput(Input memory input) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(INPUT_TYPE_STUB, input.token, input.amount));
    }

    function hashOutput(Output memory output) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(OUTPUT_TYPE_STUB, output.token, output.amount, output.recipient, output.chainId));
    }

    // TODO: include orderDataHash here?
    function hash(
        CrossChainOrder calldata order,
        bytes32 orderTypeHash,
        bytes32 orderDataHash
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked( // TODO: bytes.concat
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
}
