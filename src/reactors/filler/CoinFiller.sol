// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { OutputDescription } from "../CatalystOrderType.sol";
import { SolverTimestampBaseFiller } from "./SolverTimestampBaseFiller.sol";
import { OutputEncodingLib } from  "../../libs/OutputEncodingLib.sol";
import { IdentifierLib } from "../../libs/IdentifierLib.sol";
import { IDestinationSettler } from "../../interfaces/IERC7683.sol";

/**
 * @dev Solvers use Oracles to pay outputs. This allows us to record the payment.
 * Tokens never touch this contract but goes directly from solver to user.
 */
contract CoinFiller is SolverTimestampBaseFiller, IDestinationSettler {
    error NotEnoughGasExecution(); // 0x6bc33587
    error FilledBySomeoneElse(bytes32 solver);
    error DifferentRemoteOracles();
    error ZeroValue();
    error NotImplemented();
    error SlopeStopped();

    event OutputFilled(bytes32 orderId, bytes32 solver, uint40 timestamp, OutputDescription output);

    // The maximum gas used on calls is 1 million gas.
    uint256 constant MAX_GAS_ON_CALL = 1_000_000;

    receive() external payable {
        // Lets us gets refunds from Oracles.
    }

    function _dutchAuctionSlope(uint256 amount, uint256 slope, uint256 stopTime) internal view returns(uint256 currentAmount) {
        uint256 currentTime = block.timestamp;
        if (stopTime < currentTime) revert SlopeStopped();
        uint256 timeDiff = stopTime - currentTime; // unchecked: stopTime > currentTime
        return amount + slope * timeDiff;
    }

    function _getAmount(OutputDescription calldata output) internal view returns (uint256 amount) {
        uint256 fulfillmentLength = output.fulfillmentContext.length;
        if (fulfillmentLength == 0) return amount;
        bytes1 orderType = bytes1(output.fulfillmentContext);
        if (orderType == 0x00 && fulfillmentLength == 1) return output.amount;
        if (orderType == 0x01 && fulfillmentLength == 65) {
            uint256 slope = uint256(bytes32(output.fulfillmentContext[1:33]));
            uint256 stopTime = uint256(bytes32(output.fulfillmentContext[33:65]));
            return _dutchAuctionSlope(output.amount, slope, stopTime);
        }
        revert NotImplemented();
    }

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
    function _fill(bytes32 orderId, OutputDescription calldata output, bytes32 proposedSolver) internal returns (bytes32) {
        // Validate order context. This lets us ensure that this filler is the correct filler for the output.
        _validateChain(output.chainId);
        _IAmRemoteOracle(output.remoteOracle);

        // Get hash of output.
        bytes32 outputHash = OutputEncodingLib.outputHash(output);

        // Get the proof state of the fulfillment.
        bytes32 existingSolver = _filledOutput[orderId][outputHash].solver;
        // Early return if we have already seen proof.
        if (existingSolver == proposedSolver) return proposedSolver;
        if (existingSolver != bytes32(0)) return existingSolver;

        // The fill status is set before the transfer.
        // This allows the above code-chunk to act as a local re-entry check.
        _filledOutput[orderId][outputHash] = FilledOutput({solver: proposedSolver, timestamp: uint40(block.timestamp)});

        // Load order description.
        address recipient = address(uint160(uint256(output.recipient)));
        address token = address(uint160(uint256(output.token)));
        uint256 amount = _getAmount(output);

        // Collect tokens from the user. If this fails, then the call reverts and
        // the proof is not set to true.
        SafeTransferLib.safeTransferFrom(token, msg.sender, recipient, amount);

        // If there is an external call associated with the fill, execute it.
        uint256 remoteCallLength = output.remoteCall.length;
        if (remoteCallLength > 0) _call(output);

        emit OutputFilled(
            orderId, proposedSolver, uint40(block.timestamp), output
        );

        return proposedSolver;
    }

    function fill(bytes32 orderId, OutputDescription calldata output, bytes32 proposedSolver) external returns(bytes32) {
        return _fill(orderId, output, proposedSolver);
    }

    /**
     * @notice function overflow of _fill to allow filling multiple outputs in a single call.
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
    // TODO: fix this mess of fill functions.

    /**
     * @notice Fills several outputs in one go. Can be used to batch fill orders to save gas.
     * @dev If an output has been filled by someone else, this function will revert.
     */
    function fillThrow(bytes32[] calldata orderIds, OutputDescription[] calldata outputs, bytes32 filler) external {
        if (filler == bytes32(0)) revert ZeroValue();
        _fillThrow(orderIds, outputs, filler);
    }

    /**
     * @notice Fills several outputs in one go. Can be used to batch fill orders to save gas.
     * @dev If an output has been filled by someone else, this function will skip that output and fill the remaining..
     */
    function fillSkip(bytes32[] calldata orderIds, OutputDescription[] calldata outputs, bytes32 filler) external {
        if (filler == bytes32(0)) revert ZeroValue();
        _fillSkip(orderIds, outputs, filler);
    }

	function fill(bytes32 orderId, bytes calldata originData, bytes calldata fillerData) external {
        (bytes32 filler, bool throwIfSomeoneElseFilled) = abi.decode(fillerData, (bytes32, bool));
        if (filler == bytes32(0)) revert ZeroValue();

        OutputDescription[] memory outputs = abi.decode(originData, (OutputDescription[]));

        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            bytes32 existingSolver = this.fill(orderId, outputs[i], filler);
            if (throwIfSomeoneElseFilled && existingSolver != filler) revert FilledBySomeoneElse(existingSolver);
        }
    }

    // TODO: Make this the standard interface. Can be done by loading OutputDescription[] via assembly.
    // TODO: This function doesn't work. We use msg.sender in the fill function.
    function fill(bytes32[] calldata orderIds, bytes calldata originData, bytes calldata fillerData) external {
        (bytes32 filler, bool throwIfSomeoneElseFilled) = abi.decode(fillerData, (bytes32, bool));
        if (filler == bytes32(0)) revert ZeroValue();

        if (throwIfSomeoneElseFilled) return this.fillThrow(orderIds, abi.decode(originData, (OutputDescription[])), filler);
        
        this.fillSkip(orderIds, abi.decode(originData, (OutputDescription[])), filler);
    }

    // --- External Calls --- ///

    /**
     * @notice Allows calling an external function in a non-griefing manner.
     * Source:
     * https://github.com/catalystdao/GeneralisedIncentives/blob/38a88a746c7c18fb5d0f6aba195264fce34944d1/src/IncentivizedMessageEscrow.sol#L680
     */
    function _call(
        OutputDescription calldata output
    ) internal {
        address recipient = address(uint160(uint256(output.recipient)));
        bytes memory payload = abi.encodeWithSignature(
            "outputFilled(bytes32,uint256,bytes)", output.token, output.amount, output.remoteCall
        );
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
    function call(
        OutputDescription calldata output
    ) external {
        // Disallow calling on-chain.
        require(msg.sender == address(0));

        _call(output);
    }
}
