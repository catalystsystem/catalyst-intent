
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.22;

import "../../../src/oracles/wormhole/external/wormhole/Messages.sol";
import "../../../src/oracles/wormhole/external/wormhole/Setters.sol";

import { WormholeBridgeOracle } from  "../../../src/oracles/wormhole/WormholeBridgeOracle.sol";
import { OutputDescription } from "../../../src/interfaces/Structs.sol";
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
    }
}

contract TestSubmitWormholeOracleProofs is Test {
    WormholeBridgeOracle oracle;

    ExportedMessages messages;

    function setUp() external {
        messages = new ExportedMessages();
        oracle = new WormholeBridgeOracle(address(this), address(messages));
    }

    function test_fill_single(address sender, uint256 amount, address recipient) public returns(OutputDescription[] memory outputs, uint32[] memory fillDeadlines) {
        address token;
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(uint256(uint160(address(oracle)))),
            remoteCall: hex""
        });
        outputs = new OutputDescription[](1);
        outputs[0] = output;

        fillDeadlines = new uint32[](1);
        fillDeadlines[0] = uint32(block.timestamp);

        vm.expectCall(
            token, abi.encodeWithSignature("transferFrom(address,address,uint256)", address(sender), recipient, amount)
        );

        vm.prank(sender);
        oracle.fill(outputs, fillDeadlines);

        bool status = oracle.isProven(output, fillDeadlines[0]);
        assertTrue(status);
    }

    /* !! DO NOT USE IN PRODUCTION. This function is missing 1 important check. !! */
    function _encode(
        OutputDescription[] memory outputs,
        uint32[] memory fillDeadlines
    ) internal pure returns (bytes memory encodedPayload) {
        uint256 numOutputs = outputs.length;
        encodedPayload = bytes.concat(bytes1(0x00), bytes2(uint16(numOutputs)));
        unchecked {
            for (uint256 i; i < numOutputs; ++i) {
                OutputDescription memory output = outputs[i];
                // if fillDeadlines.length < outputs.length then fillDeadlines[i] will fail with out of index.
                uint32 fillDeadline = fillDeadlines[i];
                encodedPayload = bytes.concat(
                    encodedPayload,
                    output.token,
                    bytes32(output.amount),
                    output.recipient,
                    bytes4(output.chainId),
                    bytes4(fillDeadline),
                    bytes2(uint16(output.remoteCall.length)), // this cannot overflow since length is checked to be less than max.
                    output.remoteCall
                );
            }
        }
    }

    function test_fill_then_submit_W(address sender, uint256 amount, address recipient) external {
        (OutputDescription[] memory outputs, uint32[] memory fillDeadlines) = test_fill_single(sender, amount, recipient);

        bytes memory expectedPayload = _encode(outputs, fillDeadlines);

        vm.expectEmit();
        emit PackagePublished(0, expectedPayload, 15);
        oracle.submit(outputs, fillDeadlines);
    }

    function test_fill_and_submit(address sender, uint256 amount, address recipient) external {
        address token;
        OutputDescription memory output = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(uint256(uint160(address(oracle)))),
            remoteCall: hex""
        });
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = output;

        uint32[] memory fillDeadlines = new uint32[](1);
        fillDeadlines[0] = uint32(block.timestamp);

        bytes memory expectedPayload = _encode(outputs, fillDeadlines);

        vm.expectEmit();
        emit PackagePublished(0, expectedPayload, 15);
        oracle.fillAndSubmit(outputs, fillDeadlines);
    }
}
