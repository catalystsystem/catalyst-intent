// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { BaseReactor } from "../../src/reactors/BaseReactor.sol";
import { OrderKey } from "../../src/interfaces/Structs.sol";

import { Script } from "forge-std/Script.sol";

contract OrderResolutionHelpers is Script {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant CATALYST_ADDRESS = 0x0000000099263f0735D03bB2787cE8FB84f6ED6E;
    address constant REACTOR_ADDRESS = 0x0000000035eb820252C699925Af8ABfad1a97318;

    function completeDispute(bytes calldata initiateEvent) public {
        (, OrderKey memory orderKey) = abi.decode(initiateEvent, (bytes, OrderKey));
        vm.broadcast();
        BaseReactor(REACTOR_ADDRESS).completeDispute(orderKey);
    }

    function optimisticPayout(bytes calldata initiateEvent) public {
        (, OrderKey memory orderKey) = abi.decode(initiateEvent, (bytes, OrderKey));
        vm.broadcast();
        BaseReactor(REACTOR_ADDRESS).optimisticPayout(orderKey, "");
    }
}
