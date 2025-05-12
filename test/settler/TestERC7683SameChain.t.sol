// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { CoinFiller7683 } from "src/fillers/coin/CoinFiller7683.sol";

import { TestERC7683Base } from "./TestERC7683Base.t.sol";

import { GaslessCrossChainOrder } from "src/interfaces/IERC7683.sol";

import { CatalystCompactOrder } from "src/settlers/compact/TheCompactOrderType.sol";
import { MandateERC7683 } from "src/settlers/7683/Order7683Type.sol";
import { OutputDescription, OutputDescriptionType } from "src/settlers/types/OutputDescriptionType.sol";

contract TestERC20Settler is TestERC7683Base {

    address swapper2;
    uint256 swapper2PrivateKey;

    CoinFiller7683 coinFiller7683;

    uint256 amount1;
    uint256 amount2;

    function setUp() public virtual override {
        super.setUp();
        coinFiller7683 = new CoinFiller7683();
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

        bytes32 coinFillerIdentifier = bytes32(uint256(uint160(address(coinFiller7683))));

        // Define order 1.
        OutputDescription[] memory outputs1 = new OutputDescription[](1);
        outputs1[0] = OutputDescription({
            remoteFiller: coinFillerIdentifier,
            remoteOracle: coinFillerIdentifier,
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount2,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        uint256[2][] memory inputs1 = new uint256[2][](1);
        inputs1[0] = [uint256(uint160(address(token))), amount1];

        MandateERC7683 memory mandate1 = MandateERC7683({
            expiry: type(uint32).max,
            localOracle: address(coinFiller7683),
            inputs: inputs1,
            outputs: outputs1
        });
        GaslessCrossChainOrder memory order1 = GaslessCrossChainOrder({
            originSettler: address(settler7683),
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            openDeadline: type(uint32).max,
            fillDeadline: type(uint32).max,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate1)
        });

        // Define order 2.
        OutputDescription[] memory outputs2 = new OutputDescription[](1);
        outputs2[0] = OutputDescription({
            remoteFiller: coinFillerIdentifier,
            remoteOracle: coinFillerIdentifier,
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(token)))),
            amount: amount1,
            recipient: bytes32(uint256(uint160(swapper2))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        uint256[2][] memory inputs2 = new uint256[2][](1);
        inputs2[0] = [uint256(uint160(address(anotherToken))), amount2];

        MandateERC7683 memory mandate2 = MandateERC7683({
            expiry: type(uint32).max,
            localOracle: address(coinFiller7683),
            inputs: inputs2,
            outputs: outputs2
        });
        GaslessCrossChainOrder memory order2 = GaslessCrossChainOrder({
            originSettler: address(settler7683),
            user: swapper2,
            nonce: 0,
            originChainId: block.chainid,
            openDeadline: type(uint32).max,
            fillDeadline: type(uint32).max,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate2)
        });

        // Sign the orders
        bytes memory signature1 = getPermit2Signature(swapperPrivateKey, order1);
        bytes memory signature2 = getPermit2Signature(swapper2PrivateKey, order2);

        assertEq(token.balanceOf(address(swapper)), amount1);
        assertEq(anotherToken.balanceOf(address(swapper2)), amount2);
        assertEq(anotherToken.balanceOf(address(swapper)), 0);
        assertEq(token.balanceOf(address(swapper2)), 0);

        bytes32 orderid1 = settler7683.orderIdentifier(order1);
        bytes32 orderid2 = settler7683.orderIdentifier(order2);

        bytes memory dataToForward = abi.encode(signature2, orderid1, order1, orderid2, order2);

        // Notice! This test will continue in inputs filled.
        settler7683.openForAndFinalise(order1, signature1, address(this), dataToForward);

        assertEq(token.balanceOf(address(swapper)), 0);
        assertEq(anotherToken.balanceOf(address(swapper2)), 0);
        assertEq(anotherToken.balanceOf(address(swapper)), amount2);
        assertEq(token.balanceOf(address(swapper2)), amount1);
    }

    bool alreadyCalled = false;

    function inputsFilled(uint256[2][] calldata /* inputs */, bytes calldata dataToForward) external virtual override {
        if (alreadyCalled == false) {
            alreadyCalled = true;
            (bytes memory signature2, , , , GaslessCrossChainOrder memory order2) = abi.decode(dataToForward, (bytes, bytes32, GaslessCrossChainOrder, bytes32, GaslessCrossChainOrder));

            // Check that we got the first token.
            assertEq(token.balanceOf(address(this)), amount1);
            assertEq(anotherToken.balanceOf(address(this)), 0);
            assertEq(token.balanceOf(address(swapper)), 0);
            assertEq(anotherToken.balanceOf(address(swapper2)), amount2);

            // Notice! The test will continue after "} else {"
            settler7683.openForAndFinalise(order2, signature2, address(this), dataToForward);
        } else {
            (, bytes32 orderid1, GaslessCrossChainOrder memory order1, bytes32 orderid2, GaslessCrossChainOrder memory order2) = abi.decode(dataToForward, (bytes, bytes32, GaslessCrossChainOrder, bytes32, GaslessCrossChainOrder));

            // Check that we got the second token. (and the first from the above section of the test).
            assertEq(token.balanceOf(address(this)), amount1);
            assertEq(anotherToken.balanceOf(address(this)), amount2);
            assertEq(token.balanceOf(address(swapper)), 0);
            assertEq(anotherToken.balanceOf(address(swapper2)), 0);

            MandateERC7683 memory mandate1 = abi.decode(order1.orderData, (MandateERC7683));
            MandateERC7683 memory mandate2 = abi.decode(order2.orderData, (MandateERC7683));

            token.approve(address(coinFiller7683), amount1);
            anotherToken.approve(address(coinFiller7683), amount2);

            // Fill the input of orders. Remember, we got tokens from the sequential fills.
            coinFiller7683.fill(orderid1, abi.encode(mandate1.outputs[0]), abi.encode(address(this)));
            coinFiller7683.fill(orderid2, abi.encode(mandate2.outputs[0]), abi.encode(address(this)));
        }
    }
}