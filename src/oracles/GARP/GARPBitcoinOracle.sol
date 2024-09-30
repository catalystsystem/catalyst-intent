// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { BitcoinOracle } from "../Bitcoinoracle.sol";
import { GeneralisedIncentivesOracle } from "./GeneralisedIncentivesOracle.sol";

/**
 * @dev Bitcoin oracle can operate in 2 modes:
 * 1. Directly Oracle. This requires a local light client along side the relevant reactor.
 * 2. Indirectly oracle through the bridge oracle.
 * This requires a local light client and a bridge connection to the relevant reactor.
 * 0xB17C012
 */
contract GARPBitcoinOracle is BitcoinOracle, GeneralisedIncentivesOracle {
    constructor(address _owner, address _escrow, address _lightClient) BitcoinOracle(_lightClient) GeneralisedIncentivesOracle(_owner, _escrow) payable {
    }
}
