// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CodeSize0 } from "../interfaces/Errors.sol";

library IsContractLib {
    /**
     * @dev this function is used to check if an address is not EOA or undeployed contract.
     * @param addr is the token contract address needs to be checked against.
     */
    function checkCodeSize(address addr) internal view {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        if (size == 0) revert CodeSize0();
    }
}
