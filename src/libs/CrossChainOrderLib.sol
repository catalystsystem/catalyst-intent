// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder } from "../interfaces/ISettlementContract.sol";

library CrossChainOrderLib {
    function hash(CrossChainOrder calldata order) internal pure returns(bytes32) {
        return keccak256(abi.encode(
           order
        ));
    }
}
