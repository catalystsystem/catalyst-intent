// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CrossChainOrder } from "../../src/interfaces/ISettlementContract.sol";
import { Collateral, OrderContext, OrderKey, OrderStatus } from "../../src/interfaces/Structs.sol";

import { CrossChainLimitOrderType, CatalystLimitOrderData } from "../../src/libs/ordertypes/CrossChainLimitOrderType.sol";
import { BaseReactor } from "../../src/reactors/BaseReactor.sol";

library OrderKeyInfo {
    function test() public pure { }

    function getOrderKey(
        CrossChainOrder memory order,
        BaseReactor reactor
    ) internal view returns (OrderKey memory orderKey) {
        orderKey = reactor.resolveKey(order, hex"");
    }
}
