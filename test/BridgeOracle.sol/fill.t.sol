// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;


import "forge-std/Test.sol";

import { Output } from "../../src/interfaces/ISettlementContract.sol";
import { GeneralisedIncentivesOracle } from "../../src/oracles/BridgeOracle.sol";

/**
 * @dev Oracles are also fillers
 */
contract TestBridgeOracle is Test {

    GeneralisedIncentivesOracle oracle;

    function setUp() external {
        address escrow = address(0);
        oracle = new GeneralisedIncentivesOracle(escrow);
    }

    function test_fill_single() external {
        Output memory output = Output({
            token: bytes32(0),
            amount: uint256(0),
            recipient: bytes32(0),
            chainId: uint32(block.chainid)
        });
        Output[] memory outputs = new Output[](1);
        outputs[0] = output;

        uint32[] memory fillTimes = new uint32[](1);
        fillTimes[0] = uint32(block.timestamp);

        oracle.fill(outputs, fillTimes);
    }
}
