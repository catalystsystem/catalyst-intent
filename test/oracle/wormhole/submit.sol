
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.22;

import "../../../src/oracles/wormhole/external/wormhole/Messages.sol";
import "../../../src/oracles/wormhole/external/wormhole/Setters.sol";
import { WormholeOracle } from  "../../../src/oracles/wormhole/WormholeOracle.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";

import { OutputDescription } from "../../../src/reactors/CatalystOrderType.sol";
import { CoinFiller } from "../../../src/reactors/filler/CoinFiller.sol";
import { OutputEncodingLib } from "../../../src/libs/OutputEncodingLib.sol";
import { MessageEncodingLib } from "../../../src/oracles/MessageEncodingLib.sol";

import "forge-std/Test.sol";


event PackagePublished(uint32 nonce, bytes payload, uint8 consistencyLevel);
contract ExportedMessages is Messages, Setters {
    function storeGuardianSetPub(Structs.GuardianSet memory set, uint32 index) public {
        return super.storeGuardianSet(set, index);
    }

    function publishMessage(
        uint32 nonce,
        bytes calldata payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence) {
        emit PackagePublished(nonce, payload, consistencyLevel);
        return 0;
    }
}

contract TestSubmitWormholeOracleProofs is Test {
    WormholeOracle oracle;

    ExportedMessages messages;

    CoinFiller filler;

    MockERC20 token;

    function setUp() external {
        messages = new ExportedMessages();
        oracle = new WormholeOracle(address(this), address(messages));
        filler = new CoinFiller();

        token = new MockERC20("TEST", "TEST", 18);
    }

    function encodeMessageCalldata(bytes32 identifier, bytes[] calldata payloads) external pure returns(bytes memory) {
        return MessageEncodingLib.encodeMessage(
            identifier,
            payloads
        );
    }


    function test_fill_then_submit_W(address sender, uint256 amount, address recipient, bytes32 orderId, bytes32 solverIdentifier) external {
        bytes32 fillerOracleIdentifier = oracle.getIdentifier(address(filler));

        token.mint(sender, amount);
        vm.prank(sender);
        token.approve(address(filler), amount);

        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(address(token))),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: fillerOracleIdentifier,
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        vm.expectCall(
            address(token), abi.encodeWithSignature("transferFrom(address,address,uint256)", address(sender), recipient, amount)
        );

        vm.prank(sender);
        filler.fill(orderId, output, solverIdentifier);

        bytes memory payload = OutputEncodingLib.encodeFillDescriptionM(solverIdentifier, orderId, uint32(block.timestamp), output);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = payload;

        bytes memory expectedPayload = this.encodeMessageCalldata(
            fillerOracleIdentifier,
            payloads
        );

        vm.expectEmit();
        emit PackagePublished(0, expectedPayload, 15);
        oracle.submit(address(filler), payloads);
    }
}
