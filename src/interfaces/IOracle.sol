// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { OutputDescription } from "./Structs.sol";

interface IOracle {
    function isProven(OutputDescription[] calldata outputs, uint32 fillTime) external view returns (bool proven);
}
