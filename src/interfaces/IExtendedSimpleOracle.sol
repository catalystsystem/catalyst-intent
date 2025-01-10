// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IOracle } from "./IOracle.sol";

interface IExtendedSimpleOracle is IOracle {
    function submit(bytes[] calldata payloads) external payable returns(uint256 refund);
}
