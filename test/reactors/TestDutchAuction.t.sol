// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { DeployDutchOrderReactor } from "../../script/Reactor/DeployDutchOrderReactor.s.sol";
import { ReactorHelperConfig } from "../../script/Reactor/HelperConfig.s.sol";

import { CrossChainOrder, Input } from "../../src/interfaces/ISettlementContract.sol";
import { DutchOrderReactor } from "../../src/reactors/DutchOrderReactor.sol";

import { CrossChainDutchOrderType, DutchOrderData } from "../../src/libs/ordertypes/CrossChainDutchOrderType.sol";
import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";

import { ExclusiveOrder } from "../../src/validation/ExclusiveOrder.sol";

import { Permit2DomainSeparator, TestBaseReactor } from "./TestBaseReactor.t.sol";

import { Collateral, OrderContext, OrderKey, OrderStatus, OutputDescription } from "../../src/interfaces/Structs.sol";
import { CrossChainBuilder } from "../utils/CrossChainBuilder.t.sol";

import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";
import { OrderDataBuilder } from "../utils/OrderDataBuilder.t.sol";

import { OrderKeyInfo } from "../utils/OrderKeyInfo.t.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

contract TestDutchAuction is TestBaseReactor {
    function testA() external pure { }

    using SigTransfer for ISignatureTransfer.PermitBatchTransferFrom;

    function setUp() public {
        DeployDutchOrderReactor deployer = new DeployDutchOrderReactor();
        (reactor, reactorHelperConfig) = deployer.run();
        (
            tokenToSwapInput,
            tokenToSwapOutput,
            collateralToken,
            localVMOracle,
            remoteVMOracle,
            escrow,
            permit2,
            deployerKey
        ) = reactorHelperConfig.currentConfig();
        DOMAIN_SEPARATOR = Permit2DomainSeparator(permit2).DOMAIN_SEPARATOR();
    }

    function _initiateOrder(
        uint256 _nonce,
        address _swapper,
        uint256 _inputAmount,
        uint256 _outputAmount,
        uint256 _fillerCollateralAmount,
        uint256 _challengerCollateralAmount,
        address _fillerSender,
        uint32 initiateDeadline,
        uint32 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline
    ) internal virtual override returns (OrderKey memory) {
        CrossChainOrder memory order = _getCrossOrder(
            _inputAmount,
            _outputAmount,
            _swapper,
            _fillerCollateralAmount,
            _challengerCollateralAmount,
            initiateDeadline,
            fillDeadline,
            challengeDeadline,
            proofDeadline,
            _nonce
        );

        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);
        bytes32 crossOrderHash = this._getWitnessHash(order);

        (ISignatureTransfer.PermitBatchTransferFrom memory permitBatch,) =
            Permit2Lib.toPermit(orderKey, address(reactor));

        bytes memory signature = permitBatch.getPermitBatchWitnessSignature(
            SWAPPER_PRIVATE_KEY, _getFullPermitTypeHash(), crossOrderHash, DOMAIN_SEPARATOR, address(reactor)
        );
        vm.prank(_fillerSender);
        return reactor.initiate(order, signature, fillerData);
    }

    function _getFullPermitTypeHash() internal pure override returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                SigTransfer.PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB, CrossChainDutchOrderType.permit2WitnessType()
            )
        );
    }

    function _getWitnessHash(CrossChainOrder calldata order) public pure override returns (bytes32) {
        return CrossChainDutchOrderType.crossOrderHash(order);
    }

    function _getCrossOrder(
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient,
        uint256 fillerAmount,
        uint256 challengerAmount,
        uint32 initiateDeadline,
        uint32 fillDeadline,
        uint32 challengeDeadline,
        uint32 proofDeadline,
        uint256 nonce
    ) internal view virtual override returns (CrossChainOrder memory order) {
        DutchOrderData memory dutchOrderData = OrderDataBuilder.getDutchOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            recipient,
            collateralToken,
            fillerAmount,
            challengerAmount, // TODO: Is this collateral amount?
            proofDeadline,
            challengeDeadline,
            localVMOracle,
            remoteVMOracle,
            bytes32(0),
            address(0)
        );

        order = CrossChainBuilder.getCrossChainOrder(
            dutchOrderData,
            address(reactor),
            recipient,
            nonce,
            uint32(block.chainid),
            uint32(initiateDeadline),
            uint32(fillDeadline)
        );
    }
    //TODO: add private functions to set slopes for dutch order and  test the dutch order when we fuzz the slopes

    function test_exclusive_order() external {
        ExclusiveOrder validationContract = new ExclusiveOrder();
    }
}
