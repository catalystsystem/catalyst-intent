// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OutputDescription } from "../libs/CatalystOrderType.sol";
interface IOracle {
    /**
     * @notice Check if an output has been proven.
     * @dev Helper function for accessing _provenOutput by hashing `output` through `_outputHash`.
     * @param orderId Id of order containing the output.
     * @param outputDescription Output to search for.
     */
    function outputFilled(bytes32 orderId, OutputDescription calldata outputDescription) external view returns (address solver);

    /**
     * @notice Check if a series of outputs has been proven.
     * @dev Function overload for outputFilled to allow proving multiple outputs in a single call.
     * Notice that the solver of the first provided output is reported as the entire intent solver.
     */
    function outputFilled(bytes32 orderId, OutputDescription[] calldata outputDescriptions) external view returns (address solver);
}
