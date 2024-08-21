// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { OutputDescription } from "../../../src/interfaces/Structs.sol";
import { GeneralisedIncentivesOracle } from "../../../src/oracles/BridgeOracle.sol";
import { TestCommonGARP } from "../TestCommonGARP.sol";

/**
 * @dev Oracles are also fillers
 */
contract TestBridgeOracle is TestCommonGARP {
    uint256 constant MAX_FUTURE_FILL_TIME = 7 days;

    GeneralisedIncentivesOracle oracle;

    function setUp() external {
        oracle = new GeneralisedIncentivesOracle(address(escrow));

        // TODO: mock with ERC20.
    }

    modifier setImplementationAddress(bytes32 chainIdentifier, bytes memory remoteImplementation) {
        oracle.setRemoteImplementation(chainIdentifier, remoteImplementation);
        _;
    }

    function _fillOutput(OutputDescription[] memory output, uint32[] memory fillTime) internal {
        oracle.fill(output, fillTime);
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
        uint32[] memory fillTimes = new uint32[](amountRecipient.length);
        OutputDescription[] memory outputs = new OutputDescription[](amountRecipient.length);
        uint32 fillTime = uint32(block.timestamp);
        for (uint256 i; i < amountRecipient.length; ++i) {
            fillTimes[i] = fillTime;
            outputs[i] = OutputDescription({
                token: bytes32(abi.encode(token)),
                amount: amountRecipient[i].amount,
                recipient: amountRecipient[i].recipient,
                chainId: uint32(block.chainid),
                remoteOracle: bytes32(0),
                remoteCall: hex""
            });
        }

        oracle.fill(outputs, fillTimes);

        bytes memory encodedDestinationAddress = bytes.concat(bytes1(0x14), bytes32(0), abi.encode(destinationAddress));
        oracle.submit{ value: _getTotalIncentive(DEFAULT_INCENTIVE) }(
            outputs, fillTimes, destinationIdentifier, encodedDestinationAddress, DEFAULT_INCENTIVE
        );
    }
}
