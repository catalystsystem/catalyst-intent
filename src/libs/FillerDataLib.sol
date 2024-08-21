// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { ICrossCatsCallback } from "../interfaces/ICrossCatsCallback.sol";

import { Input } from "../interfaces/ISettlementContract.sol";
import { OrderKey } from "../interfaces/Structs.sol";

/**
 * @notice Decodes fillerdata.
 */
library FillerDataLib {
    error NotImplemented(bytes1 version);
    error IdentifierMismatch();

    /**
     * @notice Decode generic filler data.
     */
    function decode(bytes calldata fillerData)
        internal
        view
        returns (address fillerAddress, uint32 orderPurchaseDeadline, uint16 orderDiscount, bytes32 identifier, uint256 pointer)
    {
        if (fillerData.length == 0) return (msg.sender, 0, 0, bytes32(0), 0);
        // fillerData.length >= 1
        bytes1 version = fillerData[0];
        if (version == VERSION_1) {
            (fillerAddress, orderPurchaseDeadline, orderDiscount) = _decode1(fillerData);
            // V1_ORDER_DISCOUNT_END is the length of the data.
            return (fillerAddress, orderPurchaseDeadline, orderDiscount, bytes32(0), V1_ORDER_DISCOUNT_END);
        }
        revert NotImplemented(version);
    }

    // TODO: describe
    function execute(bytes32 identifier, bytes32 orderKeyHash, bytes calldata executionData) internal {
        if (identifier != keccak256(executionData)) revert IdentifierMismatch();

        address toCall = address(bytes20(executionData[0:20]));
        bytes calldata dataToCall = executionData[20:];

        // Importantly, notice that an order cannot be purchased
        // if this call reverts.
        ICrossCatsCallback(toCall).orderPurchaseCallback(orderKeyHash, dataToCall);
    }

    //--- Version 1 ---/
    bytes1 private constant VERSION_1 = 0x01;
    uint256 private constant V1_ADDRESS_START = 1;
    uint256 private constant V1_ADDRESS_END = 21;
    uint256 private constant V1_ORDER_PURCHASE_DEADLINE_START = V1_ADDRESS_END;
    uint256 private constant V1_ORDER_PURCHASE_DEADLINE_END = 25;
    uint256 private constant V1_ORDER_DISCOUNT_START = V1_ORDER_PURCHASE_DEADLINE_END;
    uint256 private constant V1_ORDER_DISCOUNT_END = 27;

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

    //--- Version 2 ---/
    bytes1 private constant VERSION_2 = 0x02;
    uint256 private constant V2_ADDRESS_START = 1;
    uint256 private constant V2_ADDRESS_END = 21;
    uint256 private constant V2_ORDER_PURCHASE_DEADLINE_START = V1_ADDRESS_END;
    uint256 private constant V2_ORDER_PURCHASE_DEADLINE_END = 25;
    uint256 private constant V2_ORDER_DISCOUNT_START = V1_ORDER_PURCHASE_DEADLINE_END;
    uint256 private constant V2_ORDER_DISCOUNT_END = 27;
    uint256 private constant V2_CALLDATA_HASH_LENGTH = V2_ORDER_DISCOUNT_END;
    uint256 private constant V2_CALLDATA_HASH = V2_CALLDATA_HASH_LENGTH + 1;

    function _getFiller2(bytes calldata fillerData) private pure returns (address fillerAddress) {
        return fillerAddress = address(uint160(bytes20(fillerData[V2_ADDRESS_START:V2_ADDRESS_END])));
    }

    function _decode2(bytes calldata fillerData)
        private
        pure
        returns (address fillerAddress, uint32 orderPurchaseDeadline, uint16 orderDiscount)
    {
        fillerAddress = _getFiller1(fillerData);
        orderPurchaseDeadline =
            uint32(bytes4(fillerData[V1_ORDER_PURCHASE_DEADLINE_START:V1_ORDER_PURCHASE_DEADLINE_END]));
        orderDiscount = uint16(bytes2(fillerData[V1_ORDER_DISCOUNT_START:V1_ORDER_DISCOUNT_END]));
    }

    function _encode2(
        address fillerAddress,
        uint32 orderPurchaseDeadline,
        uint16 orderDiscount,
        bytes32 identifier
    ) internal pure returns (bytes memory fillerData) {
        return bytes.concat(VERSION_2, bytes20(fillerAddress), bytes4(orderPurchaseDeadline), bytes2(orderDiscount), identifier);
    }
}
