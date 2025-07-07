// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import {OutputSettlerCoin} from "OIF/src/output/coin/OutputSettlerCoin.sol";

import {MandateERC7683} from "OIF/src/input/7683/Order7683Type.sol";
import {GaslessCrossChainOrder} from "OIF/src/interfaces/IERC7683.sol";

import {MandateOutput, MandateOutputType} from "OIF/src/input/types/MandateOutputType.sol";
import {StandardOrder} from "OIF/src/input/types/StandardOrderType.sol";
import {InputSettler7683TestBase} from "OIF/test/input/7683/InputSettler7683.base.t.sol";

import {InputSettler7683LIFI} from "../../src/input/7683/InputSettler7683LIFI.sol";

/// @notice This test showcases how to take 2 intents and fill them together.
contract InputSettler7683SameChainSwapTest is InputSettler7683TestBase {
    address swapper2;
    uint256 swapper2PrivateKey;

    uint256 amount1;
    uint256 amount2;

    function setUp() public virtual override {
        super.setUp();
        outputSettlerCoin = new OutputSettlerCoin();

        address owner = makeAddr("owner");
        inputsettler7683 = address(new InputSettler7683LIFI(owner));
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

        bytes32 OutputSettlerCoinIdentifier = bytes32(
            uint256(uint160(address(outputSettlerCoin)))
        );

        // Define order 1.
        MandateOutput[] memory outputs1 = new MandateOutput[](1);
        outputs1[0] = MandateOutput({
            settler: OutputSettlerCoinIdentifier,
            oracle: OutputSettlerCoinIdentifier,
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount2,
            recipient: bytes32(uint256(uint160(swapper))),
            call: hex"",
            context: hex""
        });
        uint256[2][] memory inputs1 = new uint256[2][](1);
        inputs1[0] = [uint256(uint160(address(token))), amount1];

        MandateERC7683 memory mandate1 = MandateERC7683({
            expiry: type(uint32).max,
            localOracle: address(outputSettlerCoin),
            inputs: inputs1,
            outputs: outputs1
        });
        GaslessCrossChainOrder memory order1 = GaslessCrossChainOrder({
            originSettler: inputsettler7683,
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            openDeadline: type(uint32).max,
            fillDeadline: type(uint32).max,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate1)
        });

        // Define order 2.
        MandateOutput[] memory outputs2 = new MandateOutput[](1);
        outputs2[0] = MandateOutput({
            settler: OutputSettlerCoinIdentifier,
            oracle: OutputSettlerCoinIdentifier,
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(token)))),
            amount: amount1,
            recipient: bytes32(uint256(uint160(swapper2))),
            call: hex"",
            context: hex""
        });
        uint256[2][] memory inputs2 = new uint256[2][](1);
        inputs2[0] = [uint256(uint160(address(anotherToken))), amount2];

        MandateERC7683 memory mandate2 = MandateERC7683({
            expiry: type(uint32).max,
            localOracle: address(outputSettlerCoin),
            inputs: inputs2,
            outputs: outputs2
        });
        GaslessCrossChainOrder memory order2 = GaslessCrossChainOrder({
            originSettler: inputsettler7683,
            user: swapper2,
            nonce: 0,
            originChainId: block.chainid,
            openDeadline: type(uint32).max,
            fillDeadline: type(uint32).max,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate2)
        });

        // Sign the orders
        bytes memory signature1 = getPermit2Signature(
            swapperPrivateKey,
            order1
        );
        bytes memory signature2 = getPermit2Signature(
            swapper2PrivateKey,
            order2
        );

        assertEq(token.balanceOf(address(swapper)), amount1);
        assertEq(anotherToken.balanceOf(address(swapper2)), amount2);
        assertEq(anotherToken.balanceOf(address(swapper)), 0);
        assertEq(token.balanceOf(address(swapper2)), 0);

        bytes32 orderid1 = InputSettler7683LIFI(inputsettler7683)
            .orderIdentifier(order1);
        bytes32 orderid2 = InputSettler7683LIFI(inputsettler7683)
            .orderIdentifier(order2);

        bytes memory dataToForward = abi.encode(
            signature2,
            orderid1,
            order1,
            orderid2,
            order2
        );

        // Notice! This test will continue in inputs filled.
        InputSettler7683LIFI(inputsettler7683).openForAndFinalise(
            order1,
            signature1,
            address(this),
            dataToForward
        );

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
            (
                bytes memory signature2,
                ,
                ,
                ,
                GaslessCrossChainOrder memory order2
            ) = abi.decode(
                    dataToForward,
                    (
                        bytes,
                        bytes32,
                        GaslessCrossChainOrder,
                        bytes32,
                        GaslessCrossChainOrder
                    )
                );

            // Check that we got the first token.
            assertEq(token.balanceOf(address(this)), amount1);
            assertEq(anotherToken.balanceOf(address(this)), 0);
            assertEq(token.balanceOf(address(swapper)), 0);
            assertEq(anotherToken.balanceOf(address(swapper2)), amount2);

            // Notice! The test will continue after "} else {"
            InputSettler7683LIFI(inputsettler7683).openForAndFinalise(
                order2,
                signature2,
                address(this),
                dataToForward
            );
        } else {
            (
                ,
                bytes32 orderid1,
                GaslessCrossChainOrder memory order1,
                bytes32 orderid2,
                GaslessCrossChainOrder memory order2
            ) = abi.decode(
                    dataToForward,
                    (
                        bytes,
                        bytes32,
                        GaslessCrossChainOrder,
                        bytes32,
                        GaslessCrossChainOrder
                    )
                );

            // Check that we got the second token. (and the first from the above section of the test).
            assertEq(token.balanceOf(address(this)), amount1);
            assertEq(anotherToken.balanceOf(address(this)), amount2);
            assertEq(token.balanceOf(address(swapper)), 0);
            assertEq(anotherToken.balanceOf(address(swapper2)), 0);

            MandateERC7683 memory mandate1 = abi.decode(
                order1.orderData,
                (MandateERC7683)
            );
            MandateERC7683 memory mandate2 = abi.decode(
                order2.orderData,
                (MandateERC7683)
            );

            token.approve(address(outputSettlerCoin), amount1);
            anotherToken.approve(address(outputSettlerCoin), amount2);

            // Fill the input of orders. Remember, we got tokens from the sequential fills.
            outputSettlerCoin.fill(
                type(uint32).max,
                orderid1,
                mandate1.outputs[0],
                bytes32(uint256(uint160(address(this))))
            );
            outputSettlerCoin.fill(
                type(uint32).max,
                orderid2,
                mandate2.outputs[0],
                bytes32(uint256(uint160(address(this))))
            );
        }
    }
}
