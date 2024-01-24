// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { OrderDescription, OrderFill, OrderContext, Signature } from "../../src/interfaces/Structs.sol";
import { TestCommon } from "../TestCommon.t.sol";

contract TestClaimOrder is TestCommon {

    address USER;
    uint256 PRIVATE_KEY;

    function setUp() {
        (USER, PRIVATEKEY) = makeAddrAndKey("user");
    }

    function test_claim_order() external{
        OrderDescription memory order = OrderDescription({
            destinationAccount: abi.encodePacked(address(uint160(0xaaaa))),
            destinationChain: bytes32(uint256(1)),
            destinationAsset: abi.encodePacked(address(uint160(0xbbbb))),
            sourceChain: SOURCE_CHAIN,
            sourceAsset: address(uint160(0xcccc)),
            minBond: 700700,
            timeout: block.timestamp + 1 days,
            sourceEvaluationContract: address(0xeeee),
            evaluationContext: hex""
        });

        bytes32 orderHash = steller.getOrderHash(order);

        (uint8 v, bytes32 r,  bytes32 s) = vm.sign(PRIVATE_KEY);

        Signature memory signature = Signature({
            r: r,
            s: s,
            v: v
        });

        settler.claimOrder(order, signature);
    }
}
