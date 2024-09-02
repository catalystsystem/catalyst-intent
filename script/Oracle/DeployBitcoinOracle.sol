// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { MockBitcoinOracle } from "../../test/mocks/MockBitcoinOracle.sol";
import { MockERC20 } from "../../test/mocks/MockERC20.sol";
import { OracleHelperConfig } from "./HelperConfig.sol";
import { BtcPrism } from "bitcoinprism-evm/src/BtcPrism.sol";

contract DeployBitcoinOracle {
    function run() external returns (MockBitcoinOracle, OracleHelperConfig) {
        OracleHelperConfig helperConfig = new OracleHelperConfig();
        (,, address escrow, address prismAddress,) = helperConfig.currentConfig();
        BtcPrism prism = BtcPrism(prismAddress);
        MockBitcoinOracle bitcoinOracle = new MockBitcoinOracle(escrow, prism);
        return (bitcoinOracle, helperConfig);
    }
}
