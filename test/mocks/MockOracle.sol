// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OutputDescription } from "../../src/interfaces/Structs.sol";
import { OrderKey } from "../../src/interfaces/Structs.sol";
import { GeneralisedIncentivesOracle } from "../../src/oracles/BridgeOracle.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

contract MockOracle is IMessageEscrowStructs, GeneralisedIncentivesOracle {
    address constant REFUND_GAS_TO = address(uint160(0xdeaddead));
    uint48 constant MAX_GAS_DELIVERY = 200_000;
    uint48 constant MAX_GAS_ACK = 200_000;
    uint48 constant PRICE_OF_DELIVERY_GAS = 1 gwei;
    uint48 constant PRICE_OF_ACK_GAS = 1 gwei;

    constructor(address escrowAddress, uint32 chainId) GeneralisedIncentivesOracle(escrowAddress, chainId) { }

    function getTotalIncentive(IncentiveDescription memory incentive) public pure returns (uint256) {
        return incentive.maxGasDelivery * incentive.priceOfDeliveryGas + incentive.maxGasAck * incentive.priceOfAckGas;
    }

    function getIncentive() public pure returns (IncentiveDescription memory defaultIncentive) {
        defaultIncentive = IncentiveDescription({
            maxGasDelivery: MAX_GAS_DELIVERY,
            maxGasAck: MAX_GAS_ACK,
            refundGasTo: REFUND_GAS_TO,
            priceOfDeliveryGas: PRICE_OF_DELIVERY_GAS,
            priceOfAckGas: PRICE_OF_ACK_GAS,
            targetDelta: 0
        });
    }

    function encode(
        OutputDescription[] memory outputs,
        uint32[] memory fillDeadlines
    ) public pure returns (bytes memory encodedPayload) {
        uint256 numOutputs = outputs.length;
        encodedPayload = bytes.concat(bytes1(0x00), bytes2(uint16(numOutputs)));
        for (uint256 i; i < numOutputs; ++i) {
            OutputDescription memory output = outputs[i];
            uint32 fillDeadline = fillDeadlines[i];
            encodedPayload = bytes.concat(
                encodedPayload,
                output.token,
                bytes32(output.amount),
                output.recipient,
                bytes4(output.chainId),
                bytes4(fillDeadline),
                bytes2(uint16(output.remoteCall.length)),
                output.remoteCall
            );
        }
    }

    function encodeDestinationAddress(address oracleDestinationAddress)
        public
        pure
        returns (bytes memory encodedDestinationAddress)
    {
        encodedDestinationAddress =
            bytes.concat(bytes1(0x14), bytes32(0), bytes32(uint256(uint160(oracleDestinationAddress))));
    }
}
