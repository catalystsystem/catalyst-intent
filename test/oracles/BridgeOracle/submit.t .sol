// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import { OutputDescription } from "../../../src/interfaces/Structs.sol";
import { GARPBridgeOracle } from "../../../src/oracles/GARP/GARPBridgeOracle.sol";
import { TestCommonGARP } from "../TestCommonGARP.sol";
import { MassivePayload } from "./MassivePayload.sol";

/**
 * @dev Oracles are also fillers
 */
contract TestBridgeOracle is TestCommonGARP {
    uint256 constant MAX_FUTURE_FILL_TIME = 3 days;

    GARPBridgeOracle oracle;

    function setUp() external {
        oracle = new GARPBridgeOracle(address(this), address(escrow));

        // TODO: mock with ERC20.
    }

    modifier setImplementationAddress(bytes32 chainIdentifier, bytes memory remoteImplementation) {
        oracle.setRemoteImplementation(chainIdentifier, uint32(block.chainid), remoteImplementation);
        _;
    }

    function _fillOutput(OutputDescription[] memory output, uint32[] memory fillDeadline) internal {
        oracle.fill(output, fillDeadline);
    }

    struct AmountRecipient {
        uint256 amount;
        bytes32 recipient;
    }

    function test_fill_then_submit(
        AmountRecipient[] calldata amountRecipient,
        bytes32 destinationIdentifier,
        address destinationAddress
    ) external setImplementationAddress(destinationIdentifier, abi.encode(address(escrow))) {
        address token;
        uint32[] memory fillDeadlines = new uint32[](amountRecipient.length);
        OutputDescription[] memory outputs = new OutputDescription[](amountRecipient.length);
        uint32 fillDeadline = uint32(block.timestamp);
        for (uint256 i; i < amountRecipient.length; ++i) {
            fillDeadlines[i] = fillDeadline;
            outputs[i] = OutputDescription({
                token: bytes32(abi.encode(token)),
                amount: amountRecipient[i].amount,
                recipient: amountRecipient[i].recipient,
                chainId: uint32(block.chainid),
                remoteOracle: bytes32(uint256(uint160(address(oracle)))),
                remoteCall: hex""
            });
        }

        oracle.fill(outputs, fillDeadlines);

        bytes memory encodedDestinationAddress = bytes.concat(bytes1(0x14), bytes32(0), abi.encode(destinationAddress));
        oracle.submit{ value: _getTotalIncentive(DEFAULT_INCENTIVE) }(
            outputs, fillDeadlines, destinationIdentifier, encodedDestinationAddress, DEFAULT_INCENTIVE
        );
    }

    function test_error_fill_then_submit_massive_payload(
        AmountRecipient calldata amountRecipient,
        bytes32 destinationIdentifier,
        address destinationAddress
    ) external setImplementationAddress(destinationIdentifier, abi.encode(address(escrow))) {
        address token;
        uint32[] memory fillDeadlines = new uint32[](1);
        OutputDescription[] memory outputs = new OutputDescription[](1);
        uint32 fillDeadline = uint32(block.timestamp);
        fillDeadlines[0] = fillDeadline;
        outputs[0] = OutputDescription({
            token: bytes32(abi.encode(token)),
            amount: amountRecipient.amount,
            recipient: amountRecipient.recipient,
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(uint256(uint160(address(oracle)))),
            remoteCall: hex""
        });

        OutputDescription memory fraudulentOutput = OutputDescription({
            token: bytes32(uint256(0xff)),
            amount: 0xff,
            recipient: bytes32(uint256(0xff)),
            chainId: uint32(block.chainid),
            remoteOracle: bytes32(uint256(uint160(address(oracle)))),
            remoteCall: hex""
        });
        outputs[0].remoteCall = bytes.concat(abi.encodePacked(
            fraudulentOutput.token,
            bytes32(fraudulentOutput.amount),
            fraudulentOutput.recipient,
            bytes4(fraudulentOutput.chainId),
            bytes4(fillDeadline),
            bytes2(uint16(type(uint256).max - 106)), // To match one with another remote call, you need to inject another fraudulent output after this.
            hex""
        ), MassivePayload);

        oracle.fill(outputs, fillDeadlines);

        bytes memory encodedDestinationAddress = bytes.concat(bytes1(0x14), bytes32(0), abi.encode(destinationAddress));
        vm.expectRevert(abi.encodeWithSignature("RemoteCallTooLarge()"));
        oracle.submit{ value: _getTotalIncentive(DEFAULT_INCENTIVE) }(
            outputs, fillDeadlines, destinationIdentifier, encodedDestinationAddress, DEFAULT_INCENTIVE
        );

        // TODO: submit message
    }
}
