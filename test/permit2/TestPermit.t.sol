// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";
import { BaseReactor } from "../../src/reactors/BaseReactor.sol";
import { Test } from "forge-std/Test.sol";

import { CrossChainOrder } from "../../src/interfaces/ISettlementContract.sol";
import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

abstract contract TestPermit is Test {
    BaseReactor reactor;
    ReactorHelperConfig reactorHelperConfig;
    address tokenToSwapInput;
    address tokenToSwapOutput;
    address collateralToken;
    address localVMOracle;
    address remoteVMOracle;
    // address escrow;
    address permit2;
    uint256 deployerKey;

    bytes fillerData;
    address fillerAddress;
    bytes32 DOMAIN_SEPARATOR;

    address SWAPPER;
    uint256 SWAPPER_PRIVATE_KEY;

    bytes32 constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    constructor() {
        (SWAPPER, SWAPPER_PRIVATE_KEY) = makeAddrAndKey("swapper");
    }

    function _getFullPermitTypeHash() internal virtual returns (bytes32);

    function _getWitnessHash(CrossChainOrder calldata order) public virtual returns (bytes32);
}
