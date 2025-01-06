// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OutputDescription } from "./Structs.sol";

interface IOracle {
    /**
     * @notice Check if an output has been proven.
     * @dev Helper function for accessing _provenOutput by hashing `output` through `_outputHash`.
     * @param output Output to check for.
     * @param fillDeadline The expected fill time. Is used as a time & collision check.
     */
    function outputFilled(bytes32 orderId, bytes32 remoteOracle, uint8 orderType, bytes32 outputHash) external view returns (address solver);
}
