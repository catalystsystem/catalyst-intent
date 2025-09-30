// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import { StandardOrder } from "OIF/src/input/types/StandardOrderType.sol";
import { MandateOutput } from "OIF/src/libs/MandateOutputEncodingLib.sol";
import { InputSettlerCompactTestBase } from "OIF/test/input/compact/InputSettlerCompact.base.t.sol";

import { InputSettlerCompactLIFI } from "../../src/input/compact/InputSettlerCompactLIFI.sol";

import { RegisterIntentLib } from "../../src/libs/RegisterIntentLib.sol";

contract RegisterIntentLibTest is InputSettlerCompactTestBase {
    address owner;

    function setUp() public override {
        super.setUp();

        owner = makeAddr("owner");
        inputSettlerCompact = address(new InputSettlerCompactLIFI(address(theCompact), owner));
    }

    function test_depositFor_gas() external {
        test_depositFor(makeAddr("depositor"), makeAddr("user"));
    }

    event IntentRegistered(bytes32 indexed orderId, StandardOrder order);

    function test_depositFor(address depositor, address user) public {
        vm.assume(depositor != address(0));
        vm.assume(user != address(0));
        vm.assume(depositor != address(inputSettlerCompact));
        vm.assume(user != address(inputSettlerCompact));
        vm.assume(depositor != address(theCompact));
        vm.assume(user != address(theCompact));

        uint256 amount1 = 10 ** 18;
        uint256 amount2 = 10 ** 12;

        // We don't really care about the output description.
        MandateOutput[] memory outputs = new MandateOutput[](0);

        uint256[2][] memory inputs = new uint256[2][](2);
        inputs[0] = [uint256(bytes32(abi.encodePacked(alwaysOkAllocatorLockTag, address(token)))), amount1];
        inputs[1] = [uint256(bytes32(abi.encodePacked(alwaysOkAllocatorLockTag, address(anotherToken)))), amount2];

        StandardOrder memory order = StandardOrder({
            user: user,
            nonce: 0,
            originChainId: block.chainid,
            expires: type(uint32).max,
            fillDeadline: type(uint32).max,
            inputOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Mint tokens and set approvals
        token.mint(depositor, amount1);
        anotherToken.mint(depositor, amount2);

        assertEq(token.balanceOf(depositor), amount1);
        assertEq(anotherToken.balanceOf(depositor), amount2);
        assertEq(token.balanceOf(address(theCompact)), 0);
        assertEq(anotherToken.balanceOf(address(theCompact)), 0);

        vm.startPrank(depositor);
        RegisterIntentLib.depositAndRegisterIntentFor(address(theCompact), inputSettlerCompact, order, true);
        vm.snapshotGasLastCall("inputSettler", "depositAndRegisterFor");
        vm.stopPrank();

        assertEq(token.balanceOf(depositor), 0);
        assertEq(anotherToken.balanceOf(depositor), 0);
        assertEq(token.balanceOf(address(theCompact)), amount1);
        assertEq(anotherToken.balanceOf(address(theCompact)), amount2);
        assertEq(theCompact.balanceOf(user, inputs[0][0]), amount1);
        assertEq(theCompact.balanceOf(user, inputs[1][0]), amount2);

        // Try to broadcast order.
        bytes32 orderId = InputSettlerCompactLIFI(inputSettlerCompact).orderIdentifier(order);

        vm.expectEmit();
        emit IntentRegistered(orderId, order);

        InputSettlerCompactLIFI(inputSettlerCompact).broadcast(order);
        vm.snapshotGasLastCall("inputSettler", "broadcast");
    }
}
