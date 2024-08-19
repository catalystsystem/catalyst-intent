// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { Output } from "../../../src/interfaces/ISettlementContract.sol";
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

    function _fillOutput(Output[] memory output, uint32[] memory fillTime) internal {
        oracle.fill(output, fillTime);
    }

    struct AmountRecipient {
        uint256 amount;
        bytes32 recipient;
    }

    function test_fill_then_submit(
        AmountRecipient[] calldata amountRecipient,
        bytes32 destinationIdentifier,
        address destinationAddress,
        uint64 deadline
    ) external setImplementationAddress(destinationIdentifier, abi.encode(address(escrow))) {
        vm.assume(deadline > block.timestamp);
        address token;
        uint32[] memory fillTimes = new uint32[](amountRecipient.length);
        Output[] memory outputs = new Output[](amountRecipient.length);
        uint32 fillTime = uint32(block.timestamp);
        for (uint256 i; i < amountRecipient.length; ++i) {
            fillTimes[i] = fillTime;
            outputs[i] = Output({
                token: bytes32(abi.encode(token)),
                amount: amountRecipient[i].amount,
                recipient: amountRecipient[i].recipient,
                chainId: uint32(block.chainid)
            });
        }

        oracle.fill(outputs, fillTimes);

        bytes memory encodedDestinationAddress = bytes.concat(bytes1(0x14), bytes32(0), abi.encode(destinationAddress));
        oracle.submit{ value: _getTotalIncentive(DEFAULT_INCENTIVE) }(
            outputs, fillTimes, destinationIdentifier, encodedDestinationAddress, DEFAULT_INCENTIVE
        );
    }
}
