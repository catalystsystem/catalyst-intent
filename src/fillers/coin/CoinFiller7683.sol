// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IDestinationSettler } from "src/interfaces/IERC7683.sol";

import { CoinFiller } from "./CoinFiller.sol";
import { OutputDescription, OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

/**
 * @dev Solvers use Oracles to pay outputs. This allows us to record the payment.
 * Tokens never touch this contract but goes directly from solver to user.
 * This filler contract only supports limit orders.
 */
contract CoinFiller7683 is CoinFiller, IDestinationSettler {

    function fill(bytes32 orderId, bytes calldata originData, bytes calldata fillerData) external {
        bytes32 proposedSolver;
        assembly ("memory-safe") {
            proposedSolver := calldataload(fillerData.offset)
        }

        OutputDescription memory output = abi.decode(originData, (OutputDescription));

        uint256 amount = _getAmountMemory(output);


        _fillMemory(orderId, output, amount, proposedSolver);
    }

    function _getAmountMemory(
        OutputDescription memory output
    ) internal view returns (uint256 amount) {
        uint256 fulfillmentLength = output.fulfillmentContext.length;
        if (fulfillmentLength == 0) return output.amount;
        bytes1 orderType = bytes1(output.fulfillmentContext);
        if (orderType == 0x00 && fulfillmentLength == 1) return output.amount;
        revert NotImplemented();
    }

    function _fillMemory(bytes32 orderId, OutputDescription memory output, uint256 outputAmount, bytes32 proposedSolver) internal returns (bytes32) {
        if (proposedSolver == bytes32(0)) revert ZeroValue();
        // Validate order context. This lets us ensure that this filler is the correct filler for the output.
        _validateChain(output.chainId);
        _IAmRemoteFiller(output.remoteFiller);

        // Get hash of output.
        bytes32 outputHash = OutputEncodingLib.getOutputDescriptionHashMemory(output);

        // Get the proof state of the fulfillment.
        bytes32 existingSolver = _filledOutputs[orderId][outputHash].solver;

        // Early return if we have already seen proof.
        if (existingSolver != bytes32(0)) return existingSolver;

        // The fill status is set before the transfer.
        // This allows the above code-chunk to act as a local re-entry check.
        _filledOutputs[orderId][outputHash] = FilledOutput({ solver: proposedSolver, timestamp: uint32(block.timestamp) });

        // Load order description.
        address recipient = address(uint160(uint256(output.recipient)));
        address token = address(uint160(uint256(output.token)));

        uint256 deliveryAmount = _preDeliveryHook(recipient, token, outputAmount);
        // Collect tokens from the user. If this fails, then the call reverts and
        // the proof is not set to true.
        SafeTransferLib.safeTransferFrom(token, msg.sender, recipient, deliveryAmount);

        // If there is an external call associated with the fill, execute it.
        uint256 remoteCallLength = output.remoteCall.length;
        if (remoteCallLength > 0) _callMemory(deliveryAmount, address(uint160(uint256(output.recipient))), output.token, output.remoteCall);

        emit OutputFilled(orderId, proposedSolver, uint32(block.timestamp), output);

        return proposedSolver;
    }


    function _callMemory(uint256 amount, address destination, bytes32 token, bytes memory remoteCall) internal {
        bytes memory payload = abi.encodeWithSignature("outputFilled(bytes32,uint256,bytes)", token, amount, remoteCall);
        bool success;
        assembly ("memory-safe") {
            success := call(MAX_GAS_ON_CALL, destination, 0, add(payload, 0x20), mload(payload), 0, 0)
        }
        unchecked {
            if (!success) if (gasleft() < MAX_GAS_ON_CALL * 1 / 63) revert NotEnoughGasExecution();
        }
    }
}
