// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import { ICrossChainReceiver } from "GeneralisedIncentives/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

import { OrderKey } from "../interfaces/structs.sol";
import { ReactorBase } from "../reactors/ReactorBase.sol";

/** 
 * @dev Oracles are also fillers
 */
contract GeneralisedIncentivesOracle is ICrossChainReceiver, IMessageEscrowStructs {
    using SafeTransferLib for ERC20;

    // TODO: we need a way to do remote verification.
    IIncentivizedMessageEscrow immutable public escrow;
    mapping(bytes32 destinationIdentifier => mapping(bytes destinationAddress => IIncentivizedMessageEscrow escrow)) escrowMapping;

    mapping(OrderKey orderKey => uint256 fillTime) public filledOrders;

    error AlreadyFilled();
    error NotFilled();
    error NotApprovedEscrow();

    constructor(address escrow) {
        // Solution 1: Set the escrow.
        escrow = IIncentivizedMessageEscrow(escrow);
    }

    /**
     * @notice Fills an order but does not automatically submit the fill for evaluation on the source chain.
     */
    function _fill(OrderKey calldata orderKey) internal {
        // Since we see this as submitted to the EVM chain, we can make some assumptions on what the orderKey specified.
        // However, since we don't know which AMB is being used, can't actually check if this is the correct chain.
        // It is assumed that the solver knows that this is actually the right chain.
        // Check if this order has been filled before.
        uint256 filledTime = filledOrders[orderKey];
        if (filledTime != 0) revert AlreadyFilled();
        filledOrders[orderKey] = block.timestamp;

        // TODO: check that we are on the right chain.
        // TODO: verify that we are sending the proof to the correct chain.

        address destination = address(uint160(uint256(orderKey.destinationAddress)));
        address asset = address(uint160(uint256(orderKey.destinationAsset)));
        uint256 amount = orderKey.amount;
        ERC20(asset).safeTransferFrom(msg.sender, destination, amount);
    }

    //--- Sending Proofs ---//

    // TODO: figure out what the best best interface for this function is
    function _submit(
        uint256 filledTime,
        OrderKey calldata orderKey,
        address reactor,
        bytes32 destinationIdentifier,
        bytes destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) internal {
        // TODO: Figure out a better idea than abi.encode
        bytes memory message = abi.encode(reactor, filledTime, orderKey);
        escrow.submitMessage(destinationIdentifier, destinationAddress, message, incentive);
    }

    //--- Solver Interface ---//

    function fill(OrderKey calldata orderKey) external {
        _fill(orderKey);
    }

    function submit(
        OrderKey calldata orderKey,
        address reactor,
        bytes32 destinationIdentifier,
        bytes destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) payable external {
        uint256 filledTime = filledOrders[orderKey];
        if (fillStatus == 0) revert NotFilled();

        _submit(
            filledTime,
            orderKey,
            reactor,
            destinationIdentifier,
            destinationAddress,
            incentive,
            deadline
        );
    }

    function fillAndSubmit(
        OrderKey calldata orderKey,
        address reactor,
        bytes32 destinationIdentifier,
        bytes destinationAddress,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) payable external {
        _fill(orderKey);
        _submit(
            block.timestamp,
            orderKey,
            reactor,
            destinationIdentifier,
            destinationAddress,
            incentive,
            deadline
        );
    }

    //--- Generalised Incentives ---//

    modifier onlyEscrow() {
        if (msg.sender != address(escrow)) revert NotApprovedEscrow();
        _;
    }

    function receiveMessage(bytes32 sourceIdentifierbytes, bytes32 messageIdentifier, bytes calldata fromApplication, bytes calldata message) onlyEscrow() external returns(bytes memory acknowledgement) {
        (address reactor, uint256 filledTime, OrderKey memory orderKey) = abi.decode(message, (addres, OrderKey));

        ReactorBase(reactor).oracle(orderKey);

        // We don't care about the ack.
        return hex"";
    }

    function receiveAck(bytes32 destinationIdentifier, bytes32 messageIdentifier, bytes calldata acknowledgement) onlyEscrow() external {
        // We don't actually do anything on ack.
    }
}
