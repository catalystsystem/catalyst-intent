// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { Input } from "../interfaces/ISettlementContract.sol";
import { OrderKey } from "../interfaces/Structs.sol";

// TODO: Clean up.
// Filler Data structure
bytes1 constant VERSION_1 = 0x01;
uint256 constant V1_ADDRESS_START = 1;
uint256 constant V1_ADDRESS_END = 21;
uint256 constant V1_ORDER_PURCHASE_DEADLINE_START = V1_ADDRESS_END;
uint256 constant V1_ORDER_PURCHASE_DEADLINE_END = 25;
uint256 constant V1_ORDER_DISCOUNT_START = V1_ORDER_PURCHASE_DEADLINE_END;
uint256 constant V1_ORDER_DISCOUNT_END = 27;

/// @notice Decodes fillerdata.
library FillerDataLib {
    function decode(bytes calldata fillerData)
        internal
        view
        returns (address fillerAddress, uint32 orderPurchaseDeadline, uint16 orderDiscount, uint256 pointer)
    {
        if (fillerData.length == 0) return (msg.sender, 0, 0, 0);
        // fillerData.length >= 1
        bytes1 version = fillerData[0];
        if (version == VERSION_1) {
            (fillerAddress, orderPurchaseDeadline, orderDiscount) = _decode1(fillerData);
            // V1_ORDER_DISCOUNT_END is the length of the data.
            return (fillerAddress, orderPurchaseDeadline, orderDiscount, V1_ORDER_DISCOUNT_END);
        }
    }

    function _getFiller1(bytes calldata fillerData) private pure returns (address fillerAddress) {
        return fillerAddress = address(uint160(bytes20(fillerData[V1_ADDRESS_START:V1_ADDRESS_END])));
    }

    function _decode1(bytes calldata fillerData)
        private
        pure
        returns (address fillerAddress, uint32 orderPurchaseDeadline, uint16 orderDiscount)
    {
        fillerAddress = _getFiller1(fillerData);
        orderPurchaseDeadline =
            uint32(bytes4(fillerData[V1_ORDER_PURCHASE_DEADLINE_START:V1_ORDER_PURCHASE_DEADLINE_END]));
        orderDiscount = uint16(bytes2(fillerData[V1_ORDER_DISCOUNT_START:V1_ORDER_DISCOUNT_END]));
    }

    function _encode1(
        address fillerAddress,
        uint32 orderPurchaseDeadline,
        uint16 orderDiscount
    ) internal pure returns (bytes memory fillerData) {
        return bytes.concat(VERSION_1, bytes20(fillerAddress), bytes4(orderPurchaseDeadline), bytes2(orderDiscount));
    }
}
