// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { IncentivizedMockEscrow } from "GeneralisedIncentives/apps/mock/IncentivizedMockEscrow.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowStructs } from "GeneralisedIncentives/interfaces/IMessageEscrowStructs.sol";

/**
 * @dev Oracles are also fillers
 */
contract TestCommonGARP is Test, IMessageEscrowStructs {
    function test() external { }

    address immutable signer;
    uint256 immutable key;

    address constant lostgas = address(uint160(0xdead));
    IIncentivizedMessageEscrow escrow;

    IncentiveDescription DEFAULT_INCENTIVE;
    address immutable REFUND_GAS_TO = address(uint160(0xdeaddead));
    bytes32 immutable CHAIN_IDENTIFIER;

    constructor() {
        (signer, key) = makeAddrAndKey("signer");

        CHAIN_IDENTIFIER = bytes32(block.chainid);
        escrow = new IncentivizedMockEscrow(lostgas, CHAIN_IDENTIFIER, signer, 0, 0);

        DEFAULT_INCENTIVE = IncentiveDescription({
            maxGasDelivery: 200000,
            maxGasAck: 200000,
            refundGasTo: REFUND_GAS_TO,
            priceOfDeliveryGas: 1 gwei,
            priceOfAckGas: 1 gwei,
            targetDelta: 0
        });
    }

    // TODO
    function executeMessage() internal { }

    function _getTotalIncentive(IncentiveDescription memory incentive) internal pure returns (uint256) {
        return incentive.maxGasDelivery * incentive.priceOfDeliveryGas + incentive.maxGasAck * incentive.priceOfAckGas;
    }
}
