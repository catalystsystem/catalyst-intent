// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

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
    function decode(
        bytes calldata fillerData
    )
        internal
        view
        returns (
            address fillerAddress,
            uint32 orderPurchaseDeadline,
            uint16 orderPurchaseDiscount,
            bytes32 identifier,
            uint256 pointer
        )
    {
        if (fillerData.length == 0) {
            return (msg.sender, 0, 0, bytes32(0), 0);
        }
        // fillerData.length >= 1
        bytes1 version = fillerData[0];
        if (version == 0x00) {
            return (msg.sender, 0, 0, bytes32(0), 1);
        }
        if (version == VERSION_1) {
            (fillerAddress, orderPurchaseDeadline, orderPurchaseDiscount) = _decode1(fillerData);
            return (fillerAddress, orderPurchaseDeadline, orderPurchaseDiscount, bytes32(0), V1_ORDER_DISCOUNT_END);
        }
        if (version == VERSION_2) {
            (fillerAddress, orderPurchaseDeadline, orderPurchaseDiscount, identifier) = _decode2(fillerData);
            return (fillerAddress, orderPurchaseDeadline, orderPurchaseDiscount, identifier, V2_CALLDATA_HASH_END);
        }
        revert NotImplemented(version);
    }

    /**
     * @notice Execute filler data. Specifically for fillerData version 2,
     * execution data can be set as required after releasing the inputs to the filler.
     * @param identifier Hash of the executionData that has to be provided. Is stored as
     * bytes32 to avoid storing a lot of calldata.
     * @param orderKeyHash Hash of the order key. Is provided to the callback incase they want to recover
     * some information from the storage or related. (we only 0 the fillerAddress).
     * @param executionData Execution data with the destination encoded in the first 20 bytes.
     */
    function execute(bytes32 identifier, bytes32 orderKeyHash, bytes calldata executionData) internal {
        if (identifier != keccak256(executionData)) revert IdentifierMismatch();

        address toCall = address(bytes20(executionData[0:20]));
        bytes calldata dataToCall = executionData[20:];

        // Importantly, notice that an order cannot be purchased if this call reverts.
        ICrossCatsCallback(toCall).inputsFilled(orderKeyHash, dataToCall);
    }

    //--- Version 1 ---/
    bytes1 private constant VERSION_1 = 0x01;
    uint256 private constant V1_ADDRESS_START = 1;
    uint256 private constant V1_ADDRESS_END = 21;
    uint256 private constant V1_ORDER_PURCHASE_DEADLINE_START = V1_ADDRESS_END;
    uint256 private constant V1_ORDER_PURCHASE_DEADLINE_END = 25;
    uint256 private constant V1_ORDER_DISCOUNT_START = V1_ORDER_PURCHASE_DEADLINE_END;
    uint256 private constant V1_ORDER_DISCOUNT_END = 27;

    function _decode1(
        bytes calldata fillerData
    ) private pure returns (address fillerAddress, uint32 orderPurchaseDeadline, uint16 orderPurchaseDiscount) {
        fillerAddress = address(uint160(bytes20(fillerData[V1_ADDRESS_START:V1_ADDRESS_END])));
        orderPurchaseDeadline =
            uint32(bytes4(fillerData[V1_ORDER_PURCHASE_DEADLINE_START:V1_ORDER_PURCHASE_DEADLINE_END]));
        orderPurchaseDiscount = uint16(bytes2(fillerData[V1_ORDER_DISCOUNT_START:V1_ORDER_DISCOUNT_END]));
    }

    function _encode1(
        address fillerAddress,
        uint32 orderPurchaseDeadline,
        uint16 orderPurchaseDiscount
    ) internal pure returns (bytes memory fillerData) {
        return bytes.concat(
            VERSION_1, bytes20(fillerAddress), bytes4(orderPurchaseDeadline), bytes2(orderPurchaseDiscount)
        );
    }

    //--- Version 2 ---/
    bytes1 private constant VERSION_2 = 0x02;
    uint256 private constant V2_ADDRESS_START = 1;
    uint256 private constant V2_ADDRESS_END = 21;
    uint256 private constant V2_ORDER_PURCHASE_DEADLINE_START = V2_ADDRESS_END;
    uint256 private constant V2_ORDER_PURCHASE_DEADLINE_END = 25;
    uint256 private constant V2_ORDER_DISCOUNT_START = V2_ORDER_PURCHASE_DEADLINE_END;
    uint256 private constant V2_ORDER_DISCOUNT_END = 27;
    uint256 private constant V2_CALLDATA_HASH_START = V2_ORDER_DISCOUNT_END;
    uint256 private constant V2_CALLDATA_HASH_END = 59;

    function _decode2(
        bytes calldata fillerData
    )
        private
        pure
        returns (address fillerAddress, uint32 orderPurchaseDeadline, uint16 orderPurchaseDiscount, bytes32 identifier)
    {
        fillerAddress = address(uint160(bytes20(fillerData[V2_ADDRESS_START:V2_ADDRESS_END])));
        orderPurchaseDeadline =
            uint32(bytes4(fillerData[V2_ORDER_PURCHASE_DEADLINE_START:V2_ORDER_PURCHASE_DEADLINE_END]));
        orderPurchaseDiscount = uint16(bytes2(fillerData[V2_ORDER_DISCOUNT_START:V2_ORDER_DISCOUNT_END]));
        identifier = bytes32(fillerData[V2_CALLDATA_HASH_START:V2_CALLDATA_HASH_END]);
    }

    function _encode2(
        address fillerAddress,
        uint32 orderPurchaseDeadline,
        uint16 orderPurchaseDiscount,
        bytes32 identifier
    ) internal pure returns (bytes memory fillerData) {
        return bytes.concat(
            VERSION_2, bytes20(fillerAddress), bytes4(orderPurchaseDeadline), bytes2(orderPurchaseDiscount), identifier
        );
    }
}
