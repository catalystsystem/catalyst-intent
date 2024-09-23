// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockOracle } from "./mocks/MockOracle.sol";

import { IncentivizedMockEscrow } from "GeneralisedIncentives/apps/mock/IncentivizedMockEscrow.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";

import { Test } from "forge-std/Test.sol";

import { DeployPermit2 } from "permit2/test/utils/DeployPermit2.sol";

import { DeployBaseReactor } from "../script/Reactor/DeployBaseReactor.s.sol";

interface Permit2DomainSeparator {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract TestConfig is Test, DeployPermit2, DeployBaseReactor {
    function test() external { }

    address immutable permit2;
    address tokenToSwapInput;
    address tokenToSwapOutput;
    address collateralToken;
    address localVMOracle;
    address remoteVMOracle;
    address escrow;

    // Default ANVIL KEY
    uint256 public ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        permit2 = deployPermit2();
        deployerKey = ANVIL_PRIVATE_KEY;
        _setConfig();
    }

    function _setConfig() internal {
        if (tokenToSwapInput != address(0)) return;
        vm.startBroadcast();
        tokenToSwapInput = address(new MockERC20("TestTokenInput", "TTI", 18));
        tokenToSwapOutput = address(new MockERC20("TestTokenOutput", "ERC", 18));
        collateralToken = address(new MockERC20("TestCollateralToken", "TTC", 18));

        escrow = address(new IncentivizedMockEscrow(address(uint160(0xdead)), bytes32(block.chainid), address(5), 0, 0));

        localVMOracle = address(new MockOracle(address(this), escrow));
        remoteVMOracle = address(new MockOracle(address(this), escrow));
        vm.stopBroadcast();
    }
}
