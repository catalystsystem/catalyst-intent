// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "../../interfaces/Structs.sol";
import { CoinOracle } from "../CoinOracle.sol";
import { GeneralisedIncentivesOracle } from "./GeneralisedIncentivesOracle.sol";

/**
 * @dev Solvers use Oracles to pay outputs. This allows us to record the payment.
 * Tokens never touch this contract but goes directly from solver to user.
 */
contract GARPCoinOracle is CoinOracle, GeneralisedIncentivesOracle {
    constructor(address _owner, address _escrow) payable GeneralisedIncentivesOracle(_owner, _escrow) { }

    /**
     * @notice Fills and then broadcasts the proof. If an output has already been filled the
     * output will be checked for fill and won't be filled again.
     */
    function fillAndSubmit(
        OutputDescription[] calldata outputs,
        uint32[] calldata fillDeadlines,
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        IncentiveDescription calldata incentive
    ) external payable {
        // If an order has already been filled, this doesn't refill but checks
        // if the output has already been filled. Additionally, it reverts if the output is not
        // paid on this oracle. (chain && oracleAddress check).
        _fill(outputs, fillDeadlines);

        // Submit the proof for the filled outputs.
        _submit(outputs, fillDeadlines, destinationIdentifier, destinationAddress, incentive);
    }
}
