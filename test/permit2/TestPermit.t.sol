// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";
import { BaseReactor } from "../../src/reactors/BaseReactor.sol";
import { Test } from "forge-std/Test.sol";

import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

abstract contract TestPermit is Test {
    BaseReactor reactor;
    ReactorHelperConfig reactorHelperConfig;
    address tokenToSwapInput;
    address tokenToSwapOutput;
    address permit2;
    uint256 deployerKey;

    address SWAPPER;
    uint256 SWAPPER_PRIVATE_KEY;

    bytes32 public FULL_ORDER_PERMIT2_TYPE_HASH = keccak256(
        abi.encodePacked(
            SigTransfer.PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
            CrossChainOrderType.permit2WitnessType(_orderType())
        )
    );

    constructor() {
        (SWAPPER, SWAPPER_PRIVATE_KEY) = makeAddrAndKey("swapper");
    }

    function _orderType() internal virtual returns (bytes memory);
}
