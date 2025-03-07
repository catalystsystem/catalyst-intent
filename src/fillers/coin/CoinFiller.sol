// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { BaseFiller } from "src/fillers/BaseFiller.sol";
import { OutputDescription, OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

/**
 * @dev Solvers use Oracles to pay outputs. This allows us to record the payment.
 * Tokens never touch this contract but goes directly from solver to user.
 */
contract CoinFiller is BaseFiller {
    error NotImplemented();
    error SlopeStopped();

    function _preDeliveryHook(address, /* recipient */ address, /* token */ uint256 outputAmount) internal virtual override returns (uint256) {
        return outputAmount;
    }

    function _dutchAuctionSlope(uint256 amount, uint256 slope, uint32 stopTime) internal view returns (uint256 currentAmount) {
        uint32 currentTime = uint32(block.timestamp);
        if (stopTime < currentTime) revert SlopeStopped();
        uint256 timeDiff = stopTime - currentTime; // unchecked: stopTime > currentTime
        return amount + slope * timeDiff;
    }

    /**
     * @notice Computes the amount of an order. Allows limit orders and dutch auctions.
     * @dev Uses the fulfillmentContext of the output to determine order type.
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
        if (orderType == 0x01 && fulfillmentLength == 37) {
            bytes calldata fulfillmentContext = output.fulfillmentContext;
            uint256 slope; // = uint256(bytes32(output.fulfillmentContext[1:33]));
            uint32 stopTime; // = uint32(bytes4(output.fulfillmentContext[33:37]));
            assembly ("memory-safe") {
                slope := calldataload(add(fulfillmentContext.offset, 0x01))
                // load the 32 bytes such that the last 4 are stopTime. (thus start loading from the next 4 bytes)
                stopTime := calldataload(add(fulfillmentContext.offset, 0x05))
            }
            return _dutchAuctionSlope(output.amount, slope, stopTime);
        }
        revert NotImplemented();
    }

    function _fill(bytes32 orderId, OutputDescription calldata output, bytes32 proposedSolver) internal override returns (bytes32) {
        uint256 amount = _getAmount(output);
        return _fill(orderId, output, amount, proposedSolver);
    }
}
