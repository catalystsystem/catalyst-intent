// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainOrder } from "../../src/interfaces/ISettlementContract.sol";
import { Collateral, OrderContext, OrderKey, OrderStatus } from "../../src/interfaces/Structs.sol";

import { CrossChainLimitOrderType, LimitOrderData } from "../../src/libs/CrossChainLimitOrderType.sol";
import { BaseReactor } from "../../src/reactors/BaseReactor.sol";

library OrderKeyInfo {
    function test() public pure {}
    function getOrderKey(
        CrossChainOrder memory order,
        BaseReactor reactor
    ) internal view returns (OrderKey memory orderKey) {
        orderKey = reactor.resolveKey(order, hex"");
    }
}
