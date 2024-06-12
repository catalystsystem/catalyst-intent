// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { TestPermit2 } from "../TestPermit2.t.sol";

import { CrossChainOrder } from "../../src/interfaces/ISettlementContract.sol";

import { OrderKey } from "../../src/interfaces/Structs.sol";
import { CrossChainLimitOrderType, LimitOrderData } from "../../src/libs/CrossChainLimitOrderType.sol";
import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";
import { LimitOrderReactor } from "../../src/reactors/LimitOrderReactor.sol";

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

contract TestCollectTokens is TestPermit2 {
    bytes32 public constant FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH = keccak256(
        abi.encodePacked(
            _PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
            CrossChainLimitOrderType.PERMIT2_WITNESS_TYPE // TODO: generalise
        )
    );

    string permit2_type =
        string.concat(_PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB, CrossChainLimitOrderType.PERMIT2_WITNESS_TYPE);

    LimitOrderReactor reactor;

    address USER;
    uint256 PRIVATE_KEY;

    function setUp() public override {
        super.setUp();

        (USER, PRIVATE_KEY) = makeAddrAndKey("user");

        reactor = new LimitOrderReactor(PERMIT2);
    }

    function test_claim_order() external {
        LimitOrderData memory limitData = LimitOrderData({
            proofDeadline: 0,
            collateralToken: address(0),
            fillerCollateralAmount: uint256(0),
            challangerCollateralAmount: uint256(0),
            localOracle: address(0),
            remoteOracle: bytes32(0),
            destinationChainId: bytes32(0),
            destinationAsset: bytes32(0),
            destinationAddress: bytes32(0),
            amount: uint256(0)
        });

        CrossChainOrder memory order = CrossChainOrder({
            settlementContract: address(reactor),
            swapper: address(USER),
            nonce: 0,
            originChainId: uint32(block.chainid),
            initiateDeadline: uint32(block.timestamp + 1 hours),
            fillDeadline: uint32(block.timestamp + 1 hours),
            orderData: abi.encode(limitData)
        });

        bytes32 orderHash = this._getHash(order);

        OrderKey memory orderKey = reactor.resolveKey(order, hex"");

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = getPermitBatchWitnessSignature(
            permitBatch, PRIVATE_KEY, FULL_LIMIT_ORDER_PERMIT2_TYPE_HASH, orderHash, DOMAIN_SEPARATOR, address(reactor)
        );

        reactor.initiate(order, signature, abi.encode(address(this)));
    }

    function _getHash(CrossChainOrder calldata order) public pure returns (bytes32) {
        bytes32 orderDataHash = CrossChainLimitOrderType.hashOrderData(abi.decode(order.orderData, (LimitOrderData)));
        return CrossChainLimitOrderType.hash(order, orderDataHash);
    }
}
