// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IOrderType {
    /**
     * @notice Evaluates an order to return the source amount along with evaluation options.
     * @return sourceAmount The value of the order in source tokens.
     * @return destinationAmount The cost of the order in destination tokens.
     */
    function evaluate(bytes calldata evaluationContext, uint64 timeout)
        external
        view
        returns (uint256 sourceAmount, uint256 destinationAmount);
}
