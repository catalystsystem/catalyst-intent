// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "../CatalystOrderType.sol";
// import { SolverTimestampBaseFiller } from "./SolverTimestampBaseFiller.sol";

import { IdentifierLib } from "../../libs/IdentifierLib.sol";
import { OutputEncodingLib } from "../../libs/OutputEncodingLib.sol";
import { BaseFiller } from "./BaseFiller.sol";

/**
 * @dev Solvers use Oracles to pay outputs. This allows us to record the payment.
 * Tokens never touch this contract but goes directly from solver to user.
 */
contract CoinFiller is BaseFiller {
    error NotImplemented();
    error SlopeStopped();

    function _dutchAuctionSlope(uint256 amount, uint256 slope, uint256 stopTime) internal view returns (uint256 currentAmount) {
        uint256 currentTime = block.timestamp;
        if (stopTime < currentTime) revert SlopeStopped();
        uint256 timeDiff = stopTime - currentTime; // unchecked: stopTime > currentTime
        return amount + slope * timeDiff;
    }

    /**
     * @notice Computes the amount of an order. Allows limit orders and dutch auctions.
     * @dev
     * Uses the fulfillmentContext of the output to determine order type.
     * 0x00 is limit order. Requires output.fulfillmentContext == 0x00
     * 0x01 is dutch auction. Requires output.fulfillmentContext == 0x01 | slope | stopTime
     */
    function _getAmount(
        OutputDescription calldata output
    ) internal view returns (uint256 amount) {
        uint256 fulfillmentLength = output.fulfillmentContext.length;
        if (fulfillmentLength == 0) return output.amount;
        bytes1 orderType = bytes1(output.fulfillmentContext);
        if (orderType == 0x00 && fulfillmentLength == 1) return output.amount;
        if (orderType == 0x01 && fulfillmentLength == 65) {
            uint256 slope = uint256(bytes32(output.fulfillmentContext[1:33]));
            uint256 stopTime = uint256(bytes32(output.fulfillmentContext[33:65]));
            // TODO: Enable after tests.
            // assembly ("memory-safe") {
            //     uint256 slope = uint256(bytes32(output.fulfillmentContext[1:33]));
            //     slope := calldataload(add(output.offset, 0x01))
            //     uint256 stopTime = uint256(bytes32(output.fulfillmentContext[33:65]));
            //     stopTime := calldataload(add(output.offset, 0x21))
            // }
            return _dutchAuctionSlope(output.amount, slope, stopTime);
        }
        revert NotImplemented();
    }

    function _fill(bytes32 orderId, OutputDescription calldata output, bytes32 proposedSolver) internal override returns (bytes32) {
        uint256 amount = _getAmount(output);
        return _fill(orderId, output, amount, proposedSolver);
    }
}
