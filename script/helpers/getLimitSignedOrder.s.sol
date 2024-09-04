// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DeployLimitOrderReactor } from "../../script/Reactor/DeployLimitOrderReactor.s.sol";
import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";
import { LimitOrderReactor } from "../../src/reactors/LimitOrderReactor.sol";

import { MockERC20 } from "../../test/mocks/MockERC20.sol";
import { MockOracle } from "../../test/mocks/MockOracle.sol";

import { MockUtils } from "../../test/utils/MockUtils.sol";

import { OrderKeyInfo } from "../../test/utils/OrderKeyInfo.t.sol";
import { SigTransfer } from "../../test/utils/SigTransfer.t.sol";

import { CrossChainOrder, Input } from "../../src/interfaces/ISettlementContract.sol";

import { CrossChainLimitOrderType, CatalystLimitOrderData } from "../../src/libs/ordertypes/CrossChainLimitOrderType.sol";
import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";

import { Collateral, OrderContext, OrderKey, OrderStatus, OutputDescription } from "../../src/interfaces/Structs.sol";
import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

import { LimitOrderReactor } from "../../src/reactors/LimitOrderReactor.sol";

import {
    InitiateDeadlineAfterFill, InitiateDeadlinePassed, InvalidDeadlineOrder
} from "../../src/interfaces/Errors.sol";

import { CrossChainBuilder } from "../../test/utils/CrossChainBuilder.t.sol";
import { OrderDataBuilder } from "../../test/utils/OrderDataBuilder.t.sol";

import { Permit2DomainSeparator, TestBaseReactor } from "../../test/reactors/TestBaseReactor.t.sol";

import { Script } from "forge-std/Script.sol";
import "forge-std/Test.sol";

contract GetSignedLimitOrder is LimitOrderReactor, Script {
    using SigTransfer for ISignatureTransfer.PermitBatchTransferFrom;

    address constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    bytes32 constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    uint256 chainId = block.chainid;

    constructor() LimitOrderReactor(permit2, address(0)) { }

    bytes32 private constant _HASHED_NAME = keccak256("Permit2");
    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    function permit2_buildDomainSeparator(uint32 chainId) private view returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, _HASHED_NAME, chainId, permit2));
    }

    function _getFullPermitTypeHash() internal view returns (bytes32) {
        console.logBytes(abi.encodePacked(
                SigTransfer.PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
                CrossChainLimitOrderType.PERMIT2_LIMIT_ORDER_WITNESS_STRING_TYPE
            ));
        return keccak256(
            abi.encodePacked(
                SigTransfer.PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
                CrossChainLimitOrderType.PERMIT2_LIMIT_ORDER_WITNESS_STRING_TYPE
            )
        );
    }

    function _getWitnessHash(
        CrossChainOrder calldata order,
        CatalystLimitOrderData memory limitOrderData
    ) public view returns (bytes32) {
        return CrossChainLimitOrderType.crossOrderHash(order, limitOrderData);
    }

    function GetLimitOrder(
        uint256 privateKey
    ) external view returns (CrossChainOrder memory order, CatalystLimitOrderData memory orderData, bytes memory signature, bytes32 signedHash) {
        Input[] memory inputs = new Input[](1);
        OutputDescription[] memory outputs = new OutputDescription[](1);

        inputs[0] = Input({ token: 0x036CbD53842c5426634e7929541eC2318f3dCF7e, amount: 500000 });

        outputs[0] = OutputDescription({
            remoteOracle: 0x3cA2BC13f63759D627449C5FfB0713125c24b019000000000000000000000000,
            token: 0x000000000000000000000000BC00000000000000000000000000000000000101,
            amount: 8810715734160,
            recipient: 0x24a571cb9f594988d709f723c0a22739d73f825b000000000000000000000000,
            chainId: uint32(84532),
            remoteCall: hex""
        });

        orderData = CatalystLimitOrderData({
            proofDeadline: uint32(1725907392),
            challengeDeadline: uint32(1725799392),
            collateralToken: 0x0000000000000000000000000000000000000000,
            fillerCollateralAmount: 0,
            challengerCollateralAmount: 0,
            localOracle: address(0x3cA2BC13f63759D627449C5FfB0713125c24b019),
            inputs: inputs,
            outputs: outputs
        });

        order = CrossChainOrder({
            settlementContract: 0xA0BE51FAEe594BD39EE68281369Efaf8e3811727,
            swapper: 0xEB6378Ce7367F365191fC450FD4eBCdA946b6d6C,
            nonce: 2785099612183872,
            originChainId: uint32(84532),
            initiateDeadline: uint32(1725457392),
            fillDeadline: uint32(1725763392),
            orderData: abi.encode(orderData)
        });

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, this);
        bytes32 crossOrderTypeHash = this._getWitnessHash(order, orderData);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(order.settlementContract), order.initiateDeadline);

        bytes32[] memory tokenPermissions = new bytes32[](permitBatch.permitted.length);
        for (uint256 i = 0; i < permitBatch.permitted.length; ++i) {
            tokenPermissions[i] = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permitBatch.permitted[i]));
        }

        signedHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                permit2_buildDomainSeparator(order.originChainId),
                keccak256(
                    abi.encode(
                        _getFullPermitTypeHash(),
                        keccak256(abi.encodePacked(tokenPermissions)),
                        address(order.settlementContract),
                        permitBatch.nonce,
                        order.initiateDeadline,
                        crossOrderTypeHash
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, signedHash);
        signature = bytes.concat(r, s, bytes1(v));
    }
}
