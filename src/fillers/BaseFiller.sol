// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IOracle } from "src/interfaces/IOracle.sol";
import { IPayloadCreator } from "src/interfaces/IPayloadCreator.sol";
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

    // The maximum gas used on calls is 1 million gas.
    uint256 constant MAX_GAS_ON_CALL = 1_000_000;

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
        if (remoteCallLength > 0) _call(deliveryAmount, output);

        emit OutputFilled(orderId, proposedSolver, uint32(block.timestamp), output);

        return proposedSolver;
    }

    function _fill(bytes32 orderId, OutputDescription calldata output, bytes32 proposedSolver) internal virtual returns (bytes32);

    function fill(bytes32 orderId, OutputDescription calldata output, bytes32 proposedSolver) external returns (bytes32) {
        return _fill(orderId, output, proposedSolver);
    }

    /**
     * @notice function overload of _fill to allow filling multiple outputs in a single call.
     */
    function _fillThrow(bytes32[] calldata orderIds, OutputDescription[] calldata outputs, bytes32 filler) internal {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            bytes32 existingSolver = _fill(orderIds[i], outputs[i], filler);
            if (existingSolver != filler) revert FilledBySomeoneElse(existingSolver);
        }
    }

    function _fillSkip(bytes32[] calldata orderIds, OutputDescription[] calldata outputs, bytes32 filler) internal {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            _fill(orderIds[i], outputs[i], filler);
        }
    }

    // --- Solver Interface --- //

    /**
     * @notice Fills several outputs in one go. Can be used to batch fill orders to save gas.
     * @dev If an output has been filled by someone else, this function will revert.
     */
    function fillThrow(bytes32[] calldata orderIds, OutputDescription[] calldata outputs, bytes32 filler) external {
        _fillThrow(orderIds, outputs, filler);
    }

    /**
     * @notice Fills several outputs in one go. Can be used to batch fill orders to save gas.
     * @dev If an output has been filled by someone else, this function will skip that output and fill the remaining.
     */
    function fillSkip(bytes32[] calldata orderIds, OutputDescription[] calldata outputs, bytes32 filler) external {
        _fillSkip(orderIds, outputs, filler);
    }

    // --- External Calls --- ///

    /**
     * @notice Allows calling an external function in a non-griefing manner.
     * Source:
     * https://github.com/catalystdao/GeneralisedIncentives/blob/38a88a746c7c18fb5d0f6aba195264fce34944d1/src/IncentivizedMessageEscrow.sol#L680
     */
    function _call(uint256 trueAmount, OutputDescription calldata output) internal {
        address recipient = address(uint160(uint256(output.recipient)));
        bytes memory payload = abi.encodeWithSignature("outputFilled(bytes32,uint256,bytes)", output.token, trueAmount, output.remoteCall);
        bool success;
        assembly ("memory-safe") {
            // Because Solidity always create RETURNDATACOPY for external calls, even low-level calls where no variables
            // are assigned, the contract can be attacked by a so called return bomb. This incur additional cost to the
            // relayer they aren't paid for. To protect the relayer, the call is made in inline assembly.
            success := call(MAX_GAS_ON_CALL, recipient, 0, add(payload, 0x20), mload(payload), 0, 0)
            // This is what the call would look like non-assembly.
            // recipient.call{gas: MAX_GAS_ON_CALL}(
            //      abi.encodeWithSignature("outputFilled(bytes32,uint256,bytes)", output.token, output.amount,
            // output.remoteCall)
            // );
        }

        // External calls are allocated gas according roughly the following: min( gasleft * 63/64, gasArg ).
        // If there is no check against gasleft, then a relayer could potentially cheat by providing less gas.
        // Without a check, they only have to provide enough gas such that any further logic executees on 1/64 of
        // gasleft To ensure maximum compatibility with external tx simulation and gas estimation tools we will
        // check a more complex but more forgiving expression.
        // Before the call, there needs to be at least maxGasAck * 64/63 gas available. With that available, then
        // the call is allocated exactly min(+(maxGasAck * 64/63 * 63/64), maxGasAck) = maxGasAck.
        // If the call uses up all of the gas, then there must be maxGasAck * 64/63 - maxGasAck = maxGasAck * 1/63
        // gas left. It is sufficient to check that smaller limit rather than the larger limit.
        // Furthermore, if we only check when the call fails we don't have to read gasleft if it is not needed.
        unchecked {
            if (!success) if (gasleft() < MAX_GAS_ON_CALL * 1 / 63) revert NotEnoughGasExecution();
        }
        // Why is this better (than checking before)?
        // 1. Only when call fails is it checked.. The vast majority of acks should not revert so it won't be checked.
        // 2. For the majority of applications it is going to be hold that: gasleft > rest of logic > maxGasAck * 1 / 63
        // and as such won't impact and execution/gas simuatlion/estimation libs.

        // Why is this worse?
        // 1. What if the application expected us to check that it got maxGasAck? It might assume that it gets
        // maxGasAck, when it turns out it got less it silently reverts (say by a low level call ala ours).
    }

    /**
     * @notice Allows estimating the gas used for an external call.
     * @dev To call, set msg.sender to address(0).
     * This call can never be executed on-chain. It should also be noted
     * that application can cheat and implement special logic for tx.origin == 0.
     */
    function call(uint256 trueAmount, OutputDescription calldata output) external {
        // Disallow calling on-chain.
        require(msg.sender == address(0));

        _call(trueAmount, output);
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
