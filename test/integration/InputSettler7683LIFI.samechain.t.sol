// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import { LibAddress } from "OIF/src/libs/LibAddress.sol";
import { OutputSettlerSimple } from "OIF/src/output/simple/OutputSettlerSimple.sol";

import { MandateOutput } from "OIF/src/input/types/MandateOutputType.sol";
import { StandardOrder } from "OIF/src/input/types/StandardOrderType.sol";
import { InputSettlerEscrowTestBase } from "OIF/test/input/escrow/InputSettlerEscrow.base.t.sol";

import { InputSettlerEscrowLIFI } from "../../src/input/escrow/InputSettlerEscrowLIFI.sol";

/// @notice This test showcases how to take 2 intents and fill them together.
contract InputSettlerEscrowSameChainSwapTest is InputSettlerEscrowTestBase {
    using LibAddress for address;

    address swapper2;
    uint256 swapper2PrivateKey;

    uint256 amount1;
    uint256 amount2;

    OutputSettlerSimple outputSettlerSimple;

    function setUp() public virtual override {
        super.setUp();
        outputSettlerSimple = new OutputSettlerSimple();

        address owner = makeAddr("owner");
        inputSettlerEscrow = address(new InputSettlerEscrowLIFI(owner));
    }

    /// @notice This test shows how to use 2 opposite swaps to fill each other.
    function test_same_chain_swap() external {
        (swapper2, swapper2PrivateKey) = makeAddrAndKey("swapper2");

        // Amount1 has already been minted for swapper.
        amount1 = token.balanceOf(swapper);
        assertGt(amount1, 0);
        vm.prank(swapper);
        token.approve(address(permit2), amount1);

        amount2 = 251e18;
        anotherToken.mint(swapper2, amount2);
        vm.prank(swapper2);
        anotherToken.approve(address(permit2), amount2);

        // Check that this contract (the test context) does not have any tokens.
        // This is important as we will run the execution from this contract.
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(anotherToken.balanceOf(address(this)), 0);

        bytes32 outputSettlerSimpleIdentifier = bytes32(uint256(uint160(address(outputSettlerSimple))));

        // Define order 1.
        MandateOutput[] memory outputs1 = new MandateOutput[](1);
        outputs1[0] = MandateOutput({
            settler: outputSettlerSimpleIdentifier,
            oracle: outputSettlerSimpleIdentifier,
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount2,
            recipient: bytes32(uint256(uint160(swapper))),
            callbackData: hex"",
            context: hex""
        });
        uint256[2][] memory inputs1 = new uint256[2][](1);
        inputs1[0] = [uint256(uint160(address(token))), amount1];

        StandardOrder memory order1 = StandardOrder({
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            expires: type(uint32).max,
            fillDeadline: type(uint32).max,
            inputOracle: address(outputSettlerSimple),
            inputs: inputs1,
            outputs: outputs1
        });

        // Define order 2.
        MandateOutput[] memory outputs2 = new MandateOutput[](1);
        outputs2[0] = MandateOutput({
            settler: outputSettlerSimpleIdentifier,
            oracle: outputSettlerSimpleIdentifier,
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(token)))),
            amount: amount1,
            recipient: bytes32(uint256(uint160(swapper2))),
            callbackData: hex"",
            context: hex""
        });
        uint256[2][] memory inputs2 = new uint256[2][](1);
        inputs2[0] = [uint256(uint160(address(anotherToken))), amount2];

        StandardOrder memory order2 = StandardOrder({
            user: swapper2,
            nonce: 0,
            originChainId: block.chainid,
            expires: type(uint32).max,
            fillDeadline: type(uint32).max,
            inputOracle: address(outputSettlerSimple),
            inputs: inputs2,
            outputs: outputs2
        });

        // Sign the orders
        bytes memory signature1 = abi.encodePacked(bytes1(0x00), getPermit2Signature(swapperPrivateKey, order1));
        bytes memory signature2 = abi.encodePacked(bytes1(0x00), getPermit2Signature(swapper2PrivateKey, order2));

        assertEq(token.balanceOf(address(swapper)), amount1);
        assertEq(anotherToken.balanceOf(address(swapper2)), amount2);
        assertEq(anotherToken.balanceOf(address(swapper)), 0);
        assertEq(token.balanceOf(address(swapper2)), 0);

        bytes32 orderid1 = InputSettlerEscrowLIFI(inputSettlerEscrow).orderIdentifier(order1);
        bytes32 orderid2 = InputSettlerEscrowLIFI(inputSettlerEscrow).orderIdentifier(order2);

        bytes memory dataToForward = abi.encode(signature2, orderid1, order1, orderid2, order2);

        // Notice! This test will continue in inputs filled.
        InputSettlerEscrowLIFI(inputSettlerEscrow)
            .openForAndFinalise(order1, order1.user, signature1, address(this), dataToForward);

        assertEq(token.balanceOf(address(swapper)), 0);
        assertEq(anotherToken.balanceOf(address(swapper2)), 0);
        assertEq(anotherToken.balanceOf(address(swapper)), amount2);
        assertEq(token.balanceOf(address(swapper2)), amount1);
    }

    bool alreadyCalled = false;

    function orderFinalised(
        uint256[2][] calldata,
        /* inputs */
        bytes calldata dataToForward
    ) external virtual override {
        if (alreadyCalled == false) {
            alreadyCalled = true;
            (bytes memory signature2,,,, StandardOrder memory order2) =
                abi.decode(dataToForward, (bytes, bytes32, StandardOrder, bytes32, StandardOrder));

            // Check that we got the first token.
            assertEq(token.balanceOf(address(this)), amount1);
            assertEq(anotherToken.balanceOf(address(this)), 0);
            assertEq(token.balanceOf(address(swapper)), 0);
            assertEq(anotherToken.balanceOf(address(swapper2)), amount2);

            // Notice! The test will continue after "} else {"
            InputSettlerEscrowLIFI(inputSettlerEscrow)
                .openForAndFinalise(order2, order2.user, signature2, address(this), dataToForward);
        } else {
            (, bytes32 orderid1, StandardOrder memory order1, bytes32 orderid2, StandardOrder memory order2) =
                abi.decode(dataToForward, (bytes, bytes32, StandardOrder, bytes32, StandardOrder));

            // Check that we got the second token. (and the first from the above section of the test).
            assertEq(token.balanceOf(address(this)), amount1);
            assertEq(anotherToken.balanceOf(address(this)), amount2);
            assertEq(token.balanceOf(address(swapper)), 0);
            assertEq(anotherToken.balanceOf(address(swapper2)), 0);

            token.approve(address(outputSettlerSimple), amount1);
            anotherToken.approve(address(outputSettlerSimple), amount2);

            // Fill the input of orders. Remember, we got tokens from the sequential fills.
            outputSettlerSimple.fill(orderid1, order1.outputs[0], type(uint32).max, abi.encode(address(this)));
            outputSettlerSimple.fill(orderid2, order2.outputs[0], type(uint32).max, abi.encode(address(this)));

            outputSettlerSimple.setAttestation(
                orderid1, address(this).toIdentifier(), uint32(block.timestamp), order1.outputs[0]
            );
            outputSettlerSimple.setAttestation(
                orderid2, address(this).toIdentifier(), uint32(block.timestamp), order2.outputs[0]
            );
        }
    }
}
