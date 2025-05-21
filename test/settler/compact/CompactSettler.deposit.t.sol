// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { CoinFiller } from "src/fillers/coin/CoinFiller.sol";
import { CompactSettlerWithDeposit } from "src/settlers/compact/CompactSettlerWithDeposit.sol";

import { AllowOpenType } from "src/settlers/types/AllowOpenType.sol";
import { OrderPurchase, OrderPurchaseType } from "src/settlers/types/OrderPurchaseType.sol";

import { CompactSettlerTestBase } from "./CompactSettler.base.t.sol";

import { AlwaysYesOracle } from "test/mocks/AlwaysYesOracle.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

import { CatalystCompactOrder, TheCompactOrderType } from "src/settlers/compact/TheCompactOrderType.sol";
import { OutputDescription, OutputDescriptionType } from "src/settlers/types/OutputDescriptionType.sol";

import { MessageEncodingLib } from "src/libs/MessageEncodingLib.sol";
import { OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

import { WormholeOracle } from "src/oracles/wormhole/WormholeOracle.sol";
import { Messages } from "src/oracles/wormhole/external/wormhole/Messages.sol";
import { Setters } from "src/oracles/wormhole/external/wormhole/Setters.sol";
import { Structs } from "src/oracles/wormhole/external/wormhole/Structs.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";

import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";
import { IdLib } from "the-compact/src/lib/IdLib.sol";
import { AlwaysOKAllocator } from "the-compact/src/test/AlwaysOKAllocator.sol";
import { ResetPeriod } from "the-compact/src/types/ResetPeriod.sol";
import { Scope } from "the-compact/src/types/Scope.sol";

interface EIP712 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract CompactSettlerTestWithDeposit is CompactSettlerTestBase {

    function test_depositFor_gas() external {
        test_depositFor(makeAddr("depositor"), makeAddr("user"));
    }

    function test_depositFor(address depositor, address user) public {
        vm.assume(depositor != address(0));
        vm.assume(user != address(0));
        vm.assume(depositor != address(compactSettler));
        vm.assume(user != address(compactSettler));
        vm.assume(depositor != address(theCompact));
        vm.assume(user != address(theCompact));
        
        uint256 amount1 = 10**18;
        uint256 amount2 = 10**12;

        // We don't really care about the output description.
        OutputDescription[] memory outputs = new OutputDescription[](0);

        uint256[2][] memory inputs = new uint256[2][](2);
        inputs[0] = [uint256(bytes32(abi.encodePacked(alwaysOkAllocatorLockTag, address(token)))), amount1];
        inputs[1] = [uint256(bytes32(abi.encodePacked(alwaysOkAllocatorLockTag, address(anotherToken)))), amount2];

        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: user,
            nonce: 0,
            originChainId: block.chainid,
            expires: type(uint32).max,
            fillDeadline: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Mint tokens and set approvals
        token.mint(depositor, amount1);
        anotherToken.mint(depositor, amount2);
        vm.prank(depositor);
        token.approve(address(compactSettler), type(uint256).max);
        vm.prank(depositor);
        anotherToken.approve(address(compactSettler), type(uint256).max);

        assertEq(token.balanceOf(depositor), amount1);
        assertEq(anotherToken.balanceOf(depositor), amount2);
        assertEq(token.balanceOf(address(theCompact)), 0);
        assertEq(anotherToken.balanceOf(address(theCompact)), 0);

        vm.prank(depositor);
        compactSettler.depositFor(order);
        vm.snapshotGasLastCall("settler", "compactDepositFor");

        assertEq(token.balanceOf(depositor), 0);
        assertEq(anotherToken.balanceOf(depositor), 0);
        assertEq(token.balanceOf(address(theCompact)), amount1);
        assertEq(anotherToken.balanceOf(address(theCompact)), amount2);
        assertEq(theCompact.balanceOf(user, inputs[0][0]), amount1);
        assertEq(theCompact.balanceOf(user, inputs[1][0]), amount2);

        // Try to claim the inputs to check if we correctly registered the claim.
    }
}
