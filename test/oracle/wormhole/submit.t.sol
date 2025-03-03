// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.22;

import { MockERC20 } from "../../mocks/MockERC20.sol";
import { WormholeOracle } from "src/oracles/wormhole/WormholeOracle.sol";
import "src/oracles/wormhole/external/wormhole/Messages.sol";
import "src/oracles/wormhole/external/wormhole/Setters.sol";

import { CoinFiller } from "src/fillers/coin/CoinFiller.sol";

import { MessageEncodingLib } from "src/libs/MessageEncodingLib.sol";
import { OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";
import { OutputDescription } from "src/settlers/types/OutputDescriptionType.sol";

import "forge-std/Test.sol";

event PackagePublished(uint32 nonce, bytes payload, uint8 consistencyLevel);

contract ExportedMessages is Messages, Setters {
    function storeGuardianSetPub(Structs.GuardianSet memory set, uint32 index) public {
        return super.storeGuardianSet(set, index);
    }

    function publishMessage(uint32 nonce, bytes calldata payload, uint8 consistencyLevel) external payable returns (uint64 sequence) {
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

    function encodeMessageCalldata(bytes32 identifier, bytes[] calldata payloads) external pure returns (bytes memory) {
        return MessageEncodingLib.encodeMessage(identifier, payloads);
    }

    function test_fill_then_submit_W(address sender, uint256 amount, address recipient, bytes32 orderId, bytes32 solverIdentifier) external {
        vm.assume(solverIdentifier != bytes32(0));
        token.mint(sender, amount);
        vm.prank(sender);
        token.approve(address(filler), amount);

        OutputDescription memory output = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(oracle)))),
            remoteFiller: bytes32(uint256(uint160(address(filler)))),
            token: bytes32(abi.encode(address(token))),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        vm.expectCall(address(token), abi.encodeWithSignature("transferFrom(address,address,uint256)", address(sender), recipient, amount));

        vm.prank(sender);
        filler.fill(orderId, output, solverIdentifier);

        bytes memory payload = OutputEncodingLib.encodeFillDescriptionM(solverIdentifier, orderId, uint32(block.timestamp), output);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = payload;

        bytes memory expectedPayload = this.encodeMessageCalldata(output.remoteFiller, payloads);

        vm.expectEmit();
        emit PackagePublished(0, expectedPayload, 15);
        oracle.submit(address(filler), payloads);
    }

    // This test is used to test receive against other chains
    function test_fill_no_fuzz_output() public {
        uint256 amount = 100;
        bytes32 solverIdentifier = bytes32(uint256(uint160(makeAddr("solver"))));
        bytes32 recipient = bytes32(uint256(uint160(makeAddr("recipient"))));
        address sender = makeAddr("sender");

        token.mint(sender, amount);
        vm.prank(sender);
        token.approve(address(filler), amount);

        OutputDescription memory output = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(address(oracle)))),
            remoteFiller: bytes32(uint256(uint160(address(filler)))),
            token: bytes32(abi.encode(address(token))),
            amount: amount,
            recipient: bytes32(abi.encode(recipient)),
            chainId: uint32(block.chainid),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        /**
        Order id for 
            {
                user: @0xab,
                nonce: 0,
                origin_chain_id: 100,
                fill_deadline: 60000,
                local_oracle: @0x1611edd9a9d42dbcd9ae773ffa22be0f6017b00590959dd5c767e4efcd34cd0b,
                collateral_token: @0xe4d0bcbdc026b98a242f13e2761601107c90de400f0c24cdafea526abf201c26,
                collateral_amount: 0,
                initiate_deadline: 60000,
                challenge_deadline: 120000,
                input: 0x0::input_type::Input {
                    token: @0xe4d0bcbdc026b98a242f13e2761601107c90de400f0c24cdafea526abf201c26,
                    amount: 100
                },
                outputs: [
                    0x0::output_description_type::OutputDescription {
                    remote_oracle: 0x0::bytes32::Bytes32 {
                        bytes: @0x2e234dae75c793f67a35089c9d99245e1c58470b
                    },
                    remote_filler: 0x0::bytes32::Bytes32 {
                        bytes: @0xf62849f9a0b5bf2913b396098f7c7019b51a820a
                    },
                    chain_id: 31337,
                    token: 0x0::bytes32::Bytes32 {
                        bytes: @0x5991a2df15a8f6a256d3ec51e99254cd3fb576a9
                    },
                    amount: 100,
                    recipient: 0x0::bytes32::Bytes32 {
                        bytes: @0x6217c47ffa5eb3f3c92247fffe22ad998242c5
                    },
                    remote_call: [],
                    fulfilment_context: []
                    }
                ]
            }
         */
        bytes32 orderId = hex"e58f15295d1c9e383c8d4dad01ee03cfa4448f0d4f52925fa957d6e76612bff9";
        vm.expectCall(address(token), abi.encodeWithSignature("transferFrom(address,address,uint256)", address(sender), recipient, amount));
        
        vm.prank(sender);
        filler.fill(orderId, output, solverIdentifier);

        bytes memory payload = OutputEncodingLib.encodeFillDescriptionM(solverIdentifier, orderId, uint32(block.timestamp), output);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = payload;

        bytes memory expectedPayload = this.encodeMessageCalldata(output.remoteFiller, payloads);

        vm.expectEmit();
        emit PackagePublished(0, expectedPayload, 15);
        oracle.submit(address(filler), payloads);
    }
}