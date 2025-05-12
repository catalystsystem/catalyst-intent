// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IOracle } from "src/interfaces/IOracle.sol";
import { IPayloadCreator } from "src/interfaces/IPayloadCreator.sol";
import { ICatalystCallback } from "src/interfaces/ICatalystCallback.sol";

import { OutputDescription, OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

/**
 * @notice Base
 */
abstract contract BaseFiller is IPayloadCreator {
    error DifferentRemoteOracles();
    error NotEnoughGasExecution(); // 0x6bc33587
    error FilledBySomeoneElse(bytes32 solver);
    error WrongChain(uint256 expected, uint256 actual); // 0x264363e1
    error WrongRemoteFiller(bytes32 addressThis, bytes32 expected);
    error ZeroValue(); // 0x7c946ed7
    error FillDeadline();

    struct FilledOutput {
        bytes32 solver;
        uint32 timestamp;
    }

    mapping(bytes32 orderId => mapping(bytes32 outputHash => FilledOutput)) _filledOutputs;

    event OutputFilled(bytes32 indexed orderId, bytes32 solver, uint32 timestamp, OutputDescription output);

    uint32 public immutable CHAIN_ID = uint32(block.chainid);

    function _preDeliveryHook(address recipient, address token, uint256 outputAmount) internal virtual returns (uint256);

    /**
     * @notice Verifies & Fills an order.
     * If an order has already been filled given the output & fillDeadline, then this function
     * doesn't "re"fill the order but returns early. Thus this function can also be used to verify
     * that an order has been filled.
     * @dev Does not automatically submit the order (send the proof).
     * The implementation strategy (verify then fill) means that an order with repeat outputs
     * (say 1 Ether to Alice & 1 Ether to Alice) can be filled by sending 1 Ether to Alice ONCE.
     * !Don't make orders with repeat outputs. This is true for any oracles.!
     * This function implements a protection against sending proofs from third-party oracles.
     * Only proofs that have this as the correct chain and remoteOracleAddress can be sent
     * to other oracles.
     * @param orderId Identifier of order on origin chain.
     * @param output Output to fill
     * @param proposedSolver Identifier of solver on origin chain that will get inputs.
     */
    function _fill(bytes32 orderId, OutputDescription calldata output, uint256 outputAmount, bytes32 proposedSolver) internal returns (bytes32) {
        if (proposedSolver == bytes32(0)) revert ZeroValue();
        // Validate order context. This lets us ensure that this filler is the correct filler for the output.
        _validateChain(output.chainId);
        _IAmRemoteFiller(output.remoteFiller);

        // Get hash of output.
        bytes32 outputHash = OutputEncodingLib.getOutputDescriptionHash(output);

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
        if (remoteCallLength > 0) ICatalystCallback(recipient).outputFilled(output.token, deliveryAmount, output.remoteCall);

        emit OutputFilled(orderId, proposedSolver, uint32(block.timestamp), output);

        return proposedSolver;
    }

    function _fill(bytes32 orderId, OutputDescription calldata output, bytes32 proposedSolver) internal virtual returns (bytes32);

    // --- Solver Interface --- //

    function fill(uint32 fillDeadline, bytes32 orderId, OutputDescription calldata output, bytes32 proposedSolver) external returns (bytes32) {
        if (fillDeadline < block.timestamp) revert FillDeadline();
        
        return _fill(orderId, output, proposedSolver);
    }

    // --- Batch Solving --- //

    /**
     * @dev This function aids to simplify solver selection from outputs fills.
     * The first output of an order will determine which solver "wins" the order.
     * This function fills the first output by proposedSolver. Otherwise reverts.
     * Then it attempts to fill the remaining outputs. If they have already been filled,
     * it skips.
     * If any of the outputs fails to fill (because of tokens OR external call) the entire
     * fill reverts.
     * 
     * This function does not validate any part of the order but ensures multiple output orders
     * can be filled in a safer manner.
     *
     * @param orderId Identifier for the order. Is not validated, ensure it is correct.
     * @param outputs Order output descriptions. ENSURE that the FIRST output of the order is also the first output of this function.
     * @param proposedSolver Solver identifier that will be able to claim funds on the input chain.
     */
    function fillBatch(uint32 fillDeadline, bytes32 orderId, OutputDescription[] calldata outputs, bytes32 proposedSolver) external {
        if (fillDeadline < block.timestamp) revert FillDeadline();

        bytes32 actualSolver = _fill(orderId, outputs[0], proposedSolver);
        if (actualSolver != proposedSolver) revert FilledBySomeoneElse(actualSolver);

        uint256 numOutputs = outputs.length;
        for (uint256 i = 1; i < numOutputs; ++i) {
            _fill(orderId, outputs[i], proposedSolver);
        }
    }


    // --- External Calls --- //

    /**
     * @notice Allows estimating the gas used for an external call.
     * @dev To call, set msg.sender to address(0).
     * This call can never be executed on-chain. It should also be noted
     * that application can cheat and implement special logic for tx.origin == 0.
     */
    function call(uint256 trueAmount, OutputDescription calldata output) external {
        // Disallow calling on-chain.
        require(msg.sender == address(0));

        ICatalystCallback(address(uint160(uint256(output.recipient)))).outputFilled(output.token, trueAmount, output.remoteCall);
    }

    //-- Helpers --//

    /**
     * @notice Validate that expected chain (@param chainId) matches this chain's chainId (block.chainId)
     * @dev We use the chain's canonical id rather than the messaging protocol id for clarity.
     */
    function _validateChain(
        uint256 chainId
    ) internal view {
        if (block.chainid != chainId) revert WrongChain(block.chainid, uint256(chainId));
    }

    /**
     * @notice Validate that the remote oracle address is this oracle.
     * @dev For some oracles, it might be required that you "cheat" and change the encoding here.
     * Don't worry (or do worry) because the other side loads the payload as bytes32(bytes).
     */
    function _IAmRemoteFiller(
        bytes32 remoteFiller
    ) internal view virtual {
        if (bytes32(uint256(uint160(address(this)))) != remoteFiller) revert WrongRemoteFiller(bytes32(uint256(uint160(address(this)))), remoteFiller);
    }

    function _isPayloadValid(address oracle, bytes calldata payload) public view returns (bool) {
        uint256 chainId = block.chainid;
        bytes32 outputHash =
            OutputEncodingLib.getOutputDescriptionHash(bytes32(uint256(uint160(oracle))), bytes32(uint256(uint160(address(this)))), chainId, OutputEncodingLib.decodeFillDescriptionCommonPayload(payload));

        bytes32 orderId = OutputEncodingLib.decodeFillDescriptionOrderId(payload);
        FilledOutput storage filledOutput = _filledOutputs[orderId][outputHash];

        bytes32 filledSolver = filledOutput.solver;
        uint32 filledTimestamp = filledOutput.timestamp;
        if (filledSolver == bytes32(0)) return false;

        bytes32 payloadSolver = OutputEncodingLib.decodeFillDescriptionSolver(payload);
        uint32 payloadTimestamp = OutputEncodingLib.decodeFillDescriptionTimestamp(payload);

        if (filledSolver != payloadSolver) return false;
        if (filledTimestamp != payloadTimestamp) return false;

        return true;
    }

    function arePayloadsValid(
        bytes[] calldata payloads
    ) external view returns (bool) {
        address sender = msg.sender;
        uint256 numPayloads = payloads.length;
        for (uint256 i; i < numPayloads; ++i) {
            if (!_isPayloadValid(sender, payloads[i])) return false;
        }
        return true;
    }
}
