// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "../../libs/CatalystOrderType.sol";
import { CoinOracle } from "../CoinOracle.sol";
import { WormholeOracle } from "./WormholeOracle.sol";

/**
 * @dev Solvers use Oracles to pay outputs. This allows us to record the payment.
 * Tokens never touch this contract but goes directly from solver to user.
 */
contract WormholeCoinOracle is CoinOracle, WormholeOracle {
    constructor(address _owner, address _wormhole) payable WormholeOracle(_owner, _wormhole) { }

    /**
     * @notice Fills and then broadcasts the proof. If an output has already been filled the
     * output will be checked for fill and won't be filled again.
     */
    function fillAndSubmit(
        bytes32[] calldata orderIds, OutputDescription[] calldata outputs, address filler
    ) external payable {
        // If an order has already been filled, this doesn't refill but checks
        // if the output has already been filled. Additionally, it reverts if the output is not
        // paid on this oracle. (chain && oracleAddress check).
        // TODO: Check that if someone front runs the first that you then don't fill the next ones.
        _fill(orderIds, outputs, filler);

        // Submit the proof for the filled outputs.
        submit(orderIds, outputs); // TODO: optimise by making _fill return proofStorage such that we can use the internal function 
    }
}
