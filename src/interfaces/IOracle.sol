// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Output } from "./ISettlementContract.sol";

interface IOracle {
    function isProven(Output[] calldata outputs, uint32 fillTime, bytes32 oracle) external view returns (bool proven);
}
