// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OrderKey } from "../interfaces/Structs.sol";

library OrderKeyLib {
    function hash(OrderKey calldata order) internal pure returns(bytes32) {
        return keccak256(abi.encode(
           order
        ));
    }
}
