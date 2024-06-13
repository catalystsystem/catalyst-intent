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

    mapping(bytes32 outputHash => bool proven) internal _provenOutput;

    // TODO: we need a way to do remote verification.
    IIncentivizedMessageEscrow public immutable escrow;
    mapping(bytes32 destinationIdentifier => mapping(bytes destinationAddress => IIncentivizedMessageEscrow escrow))
        escrowMapping;

    mapping(bytes32 orderKey => uint256 fillTime) public filledOrders;

    error AlreadyFilled();
    error NotFilled();
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
     */
    function _fill(Output calldata output, OrderKey calldata orderKey) internal {
        // Since we see this as submitted to the EVM chain, we can make some assumptions on what the orderKey specified.
        // However, since we don't know which AMB is being used, can't actually check if this is the correct chain.
        // It is assumed that the solver knows that this is actually the right chain.
        // Check if this order has been filled before.
        uint256 filledTime = filledOrders[keccak256(abi.encode(orderKey))];
        if (filledTime != 0) revert AlreadyFilled();
        // filledOrders[orderKey] = block.timestamp;

        // TODO: check that we are on the right chain.
        // TODO: verify that we are sending the proof to the correct chain.

        address destination = address(uint160(uint256(output.recipient)));
        address asset = address(uint160(uint256(output.token)));
        uint256 amount = output.amount;
        SafeTransferLib.safeTransferFrom(asset, msg.sender, destination, amount);
    }

    //--- Sending Proofs ---//

    // TODO: figure out what the best best interface for this function is
    function _submit(
        uint256 filledTime,
        OrderKey calldata orderKey,
        address reactor,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) internal {
        // TODO: Figure out a better idea than abi.encode
        bytes memory message = abi.encode(reactor, filledTime, orderKey);
        // Deadline is set to 0.
        escrow.submitMessage(destinationIdentifier, destinationAddress, message, incentive, 0);
    }

    //--- Solver Interface ---//

    function fill(Output calldata output, OrderKey calldata orderKey) external {
        _fill(output, orderKey);
    }

    function submit(
        OrderKey calldata orderKey,
        address reactor,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable {
        uint256 filledTime = filledOrders[keccak256(abi.encode(orderKey))];
        // if (fillStatus == 0) revert NotFilled();

        _submit(filledTime, orderKey, reactor, destinationIdentifier, destinationAddress, incentive, deadline);
    }

    function fillAndSubmit(
        Output calldata output,
        OrderKey calldata orderKey,
        address reactor,
        bytes32 destinationIdentifier,
        bytes memory destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable {
        _fill(output, orderKey);
        _submit(block.timestamp, orderKey, reactor, destinationIdentifier, destinationAddress, incentive, deadline);
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
        (address reactor, uint256 filledTime, OrderKey memory orderKey) =
            abi.decode(message, (address, uint256, OrderKey));

        // TODO: figure out the structure the oracle call.
        // BaseReactor(reactor).oracle(orderKey);

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
