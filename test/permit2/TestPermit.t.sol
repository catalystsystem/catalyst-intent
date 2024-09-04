// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";
import { BaseReactor } from "../../src/reactors/BaseReactor.sol";

import { CrossChainOrder } from "../../src/interfaces/ISettlementContract.sol";
import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";

import { TestConfig } from "../TestConfig.t.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

abstract contract TestPermit is TestConfig {
    BaseReactor reactor;
    ReactorHelperConfig reactorHelperConfig;

    bytes fillerData;
    address fillerAddress;
    bytes32 DOMAIN_SEPARATOR;

    address SWAPPER;
    uint256 SWAPPER_PRIVATE_KEY;
    uint256 constant DEFAULT_COLLATERAL_AMOUNT = 10 ** 18;

    bytes32 constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    constructor() {
        (SWAPPER, SWAPPER_PRIVATE_KEY) = makeAddrAndKey("swapper");
    }

    function _getFullPermitTypeHash() internal virtual returns (bytes32);
}
