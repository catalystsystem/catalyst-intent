// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CodeSize0 } from "../interfaces/Errors.sol";

library IsContractLib {
    /**
     * @notice Checks if an address has contract code.
     * @dev The intended use of this function is in combination with safeTransferFrom.
     * Solady's safeTransferFrom does not check if a token exists. For some use cases this
     * is an issue since a call that worked earlier fails later in the flow if a token is
     * suddenly deployed to the address.
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
