// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "../CatalystOrderType.sol";
// import { SolverTimestampBaseFiller } from "./SolverTimestampBaseFiller.sol";
import { OutputEncodingLib } from  "../../libs/OutputEncodingLib.sol";
import { IdentifierLib } from "../../libs/IdentifierLib.sol";
import { BaseFiller } from "./BaseFiller.sol";

/**
 * @dev Solvers use Oracles to pay outputs. This allows us to record the payment.
 * Tokens never touch this contract but goes directly from solver to user.
 */
contract CoinFiller is BaseFiller {
    error NotImplemented();
    error SlopeStopped();

    function _dutchAuctionSlope(uint256 amount, uint256 slope, uint256 stopTime) internal view returns(uint256 currentAmount) {
        uint256 currentTime = block.timestamp;
        if (stopTime < currentTime) revert SlopeStopped();
        uint256 timeDiff = stopTime - currentTime; // unchecked: stopTime > currentTime
        return amount + slope * timeDiff;
    }

    function _getAmount(OutputDescription calldata output) internal view returns (uint256 amount) {
        uint256 fulfillmentLength = output.fulfillmentContext.length;
        if (fulfillmentLength == 0) return amount;  //TODO what does this return? 0?
        bytes1 orderType = bytes1(output.fulfillmentContext);
        if (orderType == 0x00 && fulfillmentLength == 1) return output.amount;
        if (orderType == 0x01 && fulfillmentLength == 65) {
            uint256 slope = uint256(bytes32(output.fulfillmentContext[1:33]));
            uint256 stopTime = uint256(bytes32(output.fulfillmentContext[33:65]));
            return _dutchAuctionSlope(output.amount, slope, stopTime);
        }
        revert NotImplemented();
    }

    function _fill(bytes32 orderId, OutputDescription calldata output, bytes32 proposedSolver) override internal returns (bytes32) {

        uint256 amount = _getAmount(output);
        return _fill(orderId, output, amount, proposedSolver);
    }
}
