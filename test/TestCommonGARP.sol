// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { IncentivizedMockEscrow } from "GeneralisedIncentives/apps/mock/IncentivizedMockEscrow.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";

/**
 * @dev Oracles are also fillers
 */
contract TestCommonGARP is Test {
    function test() external { }

    address immutable signer;
    uint256 immutable key;

    address constant lostgas = address(uint160(0xdead));
    IIncentivizedMessageEscrow escrow;

    constructor() {
        (signer, key) = makeAddrAndKey("signer");

        escrow = new IncentivizedMockEscrow(lostgas, bytes32(block.chainid), signer, 0, 0);
    }

    // TODO
    function executeMessage() internal { }
}
