// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { Output } from "../interfaces/ISettlementContract.sol";
import { OrderKey } from "../interfaces/Structs.sol";
import { BaseReactor } from "../reactors/BaseReactor.sol";

/**
 * @dev Oracles are also fillers
 */
contract GeneralisedIncentivesOracle is ICrossChainReceiver, IMessageEscrowStructs {

    uint256 constant MAX_FUTURE_FILL_TIME = 7 days;

    mapping(bytes32 outputHash => bool proven) internal _provenOutput;

    // TODO: we need a way to do remote verification.
    IIncentivizedMessageEscrow public immutable escrow;
    mapping(bytes32 destinationIdentifier => mapping(bytes destinationAddress => IIncentivizedMessageEscrow escrow))
        escrowMapping;

    error NotApprovedEscrow();

    constructor(address _escrow) {
        // Solution 1: Set the escrow.
        escrow = IIncentivizedMessageEscrow(_escrow);
    }

    /**
     * TODO: define an output salt which is some value (time + nonce?) that allows us to
     * discriminate between different outputs in time & space.
     */
    function _outputHash(Output calldata output, bytes32 outputSalt) internal pure returns (bytes32) {
        return keccak256(bytes.concat(abi.encode(output), outputSalt)); // TODO: Efficiency? // TODO: hash with orderKeyHash for collision?
    }

    function _outputHashM(Output memory output, bytes32 outputSalt) internal pure returns (bytes32) {
        return keccak256(bytes.concat(abi.encode(output), outputSalt)); // TODO: Efficiency? // TODO: hash with orderKeyHash for collision?
    }

    // TODO: A function that forwards an OrderKey to the reactor?
    function oracle(OrderKey calldata orderKey) external {
        // Check if orderKeyOutputs are proven.
        
    }

    function provenOutput(Output calldata output) external view returns(bool proven) {
        bytes32 outputHash = _outputHash(output, bytes32(0));
        return _provenOutput[outputHash];
    }

    function isProven(Output[] calldata outputs) public view returns(bool proven) {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            bytes32 outputHash = _outputHash(outputs[i], bytes32(0)); // TODO: output salt potentiall also by adding the orderKeyHash to it.
            if (!_provenOutput[outputHash]) {
                return proven = false;
            }
        }
        return proven = true;
    }

    /**
     * @notice Fills an order but does not automatically submit the fill for evaluation on the source chain.
     * @param output The output to fill.
     * @param fillTime The filltime to match. This is used when verifying
     * the transaction took place. 
     */
    function _fill(Output calldata output, uint32 fillTime) internal {
        // FillTime may not be in the past.
        if (fillTime < block.timestamp) require(false, "FillTimeInPast()"); // TODO: custom error.
        // Check that fillTime isn't far in the future.
        // The idea is to protect users against random transfers through this contract.
        if (fillTime > block.timestamp + MAX_FUTURE_FILL_TIME) require(false, "FillTimeFarInFuture()");

        // Check if this is the correct chain.
        // TODO: immutable chainid?
        if (uint32(block.chainid) != output.chainId) require(false, "WrongChain()"); // TODO: custom error

        // Check if this has already been filled. If it hasn't return set = false.
        bytes32 outputHash = _outputHash(output, bytes32(0)); // TODO: salt
        bool alreadyProven = _provenOutput[outputHash];
        if (alreadyProven) return;

        address recipient = address(uint160(uint256(output.recipient)));
        address token = address(uint160(uint256(output.token)));
        uint256 amount = output.amount;
        SafeTransferLib.safeTransferFrom(token, msg.sender, recipient, amount);
    }

    function _fill(Output[] calldata outputs, uint32[] calldata fillTimes) internal {
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            Output calldata output = outputs[i];
            uint32 fillTime = fillTimes[i];
            _fill(output, fillTime);
        }
    }

    //--- Sending Proofs ---//

    // TODO: figure out what the best best interface for this function is
    function _submit(
        Output[] calldata outputs,
        uint32[] calldata filledTimes,
        address reactor,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) internal {
        // TODO: Figure out a better idea than abi.encode
        bytes memory message = abi.encode(reactor, outputs, filledTimes);
        // Deadline is set to 0.
        escrow.submitMessage(destinationIdentifier, destinationAddress, message, incentive, deadline);
    }

    //--- Solver Interface ---//

     function fill(Output[] calldata outputs, uint32[] calldata fillTimes) external {
        _fill(outputs, fillTimes);
    }

    function fillAndSubmit(
        Output[] calldata outputs,
        uint32[] calldata fillTimes,
        address reactor,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable {
        _fill(outputs, fillTimes);
        _submit(outputs, fillTimes, reactor, destinationIdentifier, destinationAddress, incentive, deadline);
    }

    //--- Generalised Incentives ---//

    modifier onlyEscrow() {
        if (msg.sender != address(escrow)) revert NotApprovedEscrow();
        _;
    }

    function receiveMessage(
        bytes32 sourceIdentifierbytes,
        bytes32 messageIdentifier,
        bytes calldata fromApplication,
        bytes calldata message
    ) external onlyEscrow returns (bytes memory acknowledgement) {
        (address reactor, Output[] memory outputs, uint32[] memory fillTimes) =
            abi.decode(message, (address, Output[], uint32[]));

        // TODO: how to verify remote oracle?
        // set the proof locally.
        uint256 numOutputs = outputs.length;
        for (uint256 i; i < numOutputs; ++i) {
            Output memory output = outputs[i];
            uint32 fillTime = fillTimes[i];
            bytes32 outputHash = _outputHashM(output, bytes32(0)); // TODO: salt
            _provenOutput[outputHash] = true;
        }

        // We don't care about the ack.
        return hex"";
    }

    function receiveAck(
        bytes32 destinationIdentifier,
        bytes32 messageIdentifier,
        bytes calldata acknowledgement
    ) external onlyEscrow {
        // We don't actually do anything on ack.
    }
}
