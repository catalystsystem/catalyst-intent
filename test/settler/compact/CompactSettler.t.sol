// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { CoinFiller } from "src/fillers/coin/CoinFiller.sol";
import { CompactSettlerWithDeposit } from "src/settlers/compact/CompactSettlerWithDeposit.sol";

import { AllowOpenType } from "src/settlers/types/AllowOpenType.sol";
import { OrderPurchase, OrderPurchaseType } from "src/settlers/types/OrderPurchaseType.sol";

import { CompactSettlerTestBase } from "./CompactSettler.base.t.sol";

import { AlwaysYesOracle } from "test/mocks/AlwaysYesOracle.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

import { CatalystCompactOrder, TheCompactOrderType } from "src/settlers/compact/TheCompactOrderType.sol";
import { OutputDescription, OutputDescriptionType } from "src/settlers/types/OutputDescriptionType.sol";

import { MessageEncodingLib } from "src/libs/MessageEncodingLib.sol";
import { OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

import { WormholeOracle } from "src/oracles/wormhole/WormholeOracle.sol";
import { Messages } from "src/oracles/wormhole/external/wormhole/Messages.sol";
import { Setters } from "src/oracles/wormhole/external/wormhole/Setters.sol";
import { Structs } from "src/oracles/wormhole/external/wormhole/Structs.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";

import { EfficiencyLib } from "the-compact/src/lib/EfficiencyLib.sol";
import { IdLib } from "the-compact/src/lib/IdLib.sol";
import { AlwaysOKAllocator } from "the-compact/src/test/AlwaysOKAllocator.sol";
import { ResetPeriod } from "the-compact/src/types/ResetPeriod.sol";
import { Scope } from "the-compact/src/types/Scope.sol";

interface EIP712 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract CompactSettlerTest is CompactSettlerTestBase {
    event Transfer(address from, address to, uint256 amount);
    event Transfer(address by, address from, address to, uint256 id, uint256 amount);
    event CompactRegistered(address indexed sponsor, bytes32 claimHash, bytes32 typehash);
    event NextGovernanceFee(uint64 nextGovernanceFee, uint64 nextGovernanceFeeTime);
    event GovernanceFeeChanged(uint64 oldGovernanceFee, uint64 newGovernanceFee);

    uint64 constant GOVERNANCE_FEE_CHANGE_DELAY = 7 days;
    uint64 constant MAX_GOVERNANCE_FEE = 10 ** 18 * 0.05; // 10%

    address owner;

    function compactHash(
        address arbiter,
        address sponsor,
        uint256 nonce,
        uint256 expires,
        CatalystCompactOrder calldata order
    ) external pure returns (bytes32) {
        return TheCompactOrderType.compactHash(arbiter, sponsor, nonce, expires, order);
    }

    // -- Units Tests -- //

    error InvalidProofSeries();

    mapping(bytes proofSeries => bool valid) _validProofSeries;

    function efficientRequireProven(
        bytes calldata proofSeries
    ) external view {
        if (!_validProofSeries[proofSeries]) revert InvalidProofSeries();
    }

    struct OrderFulfillmentDescription {
        uint32 timestamp;
        OutputDescription outputDescription;
    }

    function test_validate_fills_one_solver(
        bytes32 solverIdentifier,
        bytes32 orderId,
        OrderFulfillmentDescription[] calldata orderFulfillmentDescription
    ) external {
        vm.assume(orderFulfillmentDescription.length > 0);

        address localOracle = address(this);

        bytes memory expectedProofPayload = hex"";
        uint32[] memory timestamps = new uint32[](orderFulfillmentDescription.length);
        OutputDescription[] memory outputDescriptions = new OutputDescription[](orderFulfillmentDescription.length);
        for (uint256 i; i < orderFulfillmentDescription.length; ++i) {
            timestamps[i] = orderFulfillmentDescription[i].timestamp;
            outputDescriptions[i] = orderFulfillmentDescription[i].outputDescription;

            expectedProofPayload = abi.encodePacked(
                expectedProofPayload,
                outputDescriptions[i].chainId,
                outputDescriptions[i].remoteOracle,
                outputDescriptions[i].remoteFiller,
                keccak256(
                    OutputEncodingLib.encodeFillDescriptionM(
                        solverIdentifier, orderId, timestamps[i], outputDescriptions[i]
                    )
                )
            );
        }
        _validProofSeries[expectedProofPayload] = true;

        compactSettler.validateFills(
            CatalystCompactOrder({
                user: address(0),
                nonce: 0,
                originChainId: 0,
                expires: type(uint32).max,
                fillDeadline: type(uint32).max,
                localOracle: localOracle,
                inputs: new uint256[2][](0),
                outputs: outputDescriptions
            }),
            orderId,
            solverIdentifier,
            timestamps
        );
    }

    struct OrderFulfillmentDescriptionWithSolver {
        uint32 timestamp;
        bytes32 solver;
        OutputDescription outputDescription;
    }

    function test_validate_fills_multiple_solvers(
        bytes32 orderId,
        OrderFulfillmentDescriptionWithSolver[] calldata orderFulfillmentDescriptionWithSolver
    ) external {
        vm.assume(orderFulfillmentDescriptionWithSolver.length > 0);
        address localOracle = address(this);

        bytes memory expectedProofPayload = hex"";
        uint32[] memory timestamps = new uint32[](orderFulfillmentDescriptionWithSolver.length);
        OutputDescription[] memory outputDescriptions =
            new OutputDescription[](orderFulfillmentDescriptionWithSolver.length);
        bytes32[] memory solvers = new bytes32[](orderFulfillmentDescriptionWithSolver.length);
        for (uint256 i; i < orderFulfillmentDescriptionWithSolver.length; ++i) {
            timestamps[i] = orderFulfillmentDescriptionWithSolver[i].timestamp;
            outputDescriptions[i] = orderFulfillmentDescriptionWithSolver[i].outputDescription;
            solvers[i] = orderFulfillmentDescriptionWithSolver[i].solver;

            expectedProofPayload = abi.encodePacked(
                expectedProofPayload,
                outputDescriptions[i].chainId,
                outputDescriptions[i].remoteOracle,
                outputDescriptions[i].remoteFiller,
                keccak256(
                    OutputEncodingLib.encodeFillDescriptionM(solvers[i], orderId, timestamps[i], outputDescriptions[i])
                )
            );
        }
        _validProofSeries[expectedProofPayload] = true;

        compactSettler.validateFills(
            CatalystCompactOrder({
                user: address(0),
                nonce: 0,
                originChainId: 0,
                expires: type(uint32).max,
                fillDeadline: type(uint32).max,
                localOracle: localOracle,
                inputs: new uint256[2][](0),
                outputs: outputDescriptions
            }),
            orderId,
            solvers,
            timestamps
        );
    }

    // -- Larger Integration tests -- //

    function test_finalise_self(
        address non_solver
    ) external {
        vm.assume(non_solver != solver);

        uint256 amount = 1e18 / 10;
        token.mint(swapper, amount);
        vm.prank(swapper);
        token.approve(address(theCompact), type(uint256).max);

        vm.prank(swapper);
        uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, amount];
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
            remoteOracle: bytes32(uint256(uint160(address(alwaysYesOracle)))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(
            swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order)
        );

        bytes memory signature = abi.encode(sponsorSig, hex"");

        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Other callers are disallowed:
        vm.prank(non_solver);
        vm.expectRevert(abi.encodeWithSignature("NotOrderOwner()"));
        compactSettler.finaliseSelf(order, signature, timestamps, solverIdentifier);

        assertEq(token.balanceOf(solver), 0);

        {
            bytes memory payload = OutputEncodingLib.encodeFillDescriptionM(
                solverIdentifier, compactSettler.orderIdentifier(order), uint32(block.timestamp), outputs[0]
            );
            bytes32 payloadHash = keccak256(payload);

            vm.expectCall(
                address(alwaysYesOracle),
                abi.encodeWithSignature(
                    "efficientRequireProven(bytes)",
                    abi.encodePacked(
                        order.outputs[0].chainId,
                        order.outputs[0].remoteOracle,
                        order.outputs[0].remoteFiller,
                        payloadHash
                    )
                )
            );
        }

        vm.prank(solver);
        compactSettler.finaliseSelf(order, signature, timestamps, solverIdentifier);
        vm.snapshotGasLastCall("CompactFinaliseSelf");

        assertEq(token.balanceOf(solver), amount);
    }

    function test_revert_finalise_self_too_late(address non_solver, uint32 fillDeadline, uint32 filledAt) external {
        vm.assume(non_solver != solver);
        vm.assume(fillDeadline < filledAt);

        uint256 amount = 1e18 / 10;

        token.mint(swapper, amount);
        vm.prank(swapper);
        token.approve(address(theCompact), type(uint256).max);

        vm.prank(swapper);
        uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

        address localOracle = address(alwaysYesOracle);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, amount];
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
            remoteOracle: bytes32(uint256(uint160(localOracle))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: fillDeadline,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(
            swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order)
        );
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);

        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = filledAt;

        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSignature("FilledTooLate(uint32,uint32)", fillDeadline, filledAt));
        compactSettler.finaliseSelf(order, signature, timestamps, solverIdentifier);
    }

    function test_finalise_to(address non_solver, address destination) external {
        vm.assume(destination != address(compactSettler));
        vm.assume(destination != address(theCompact));
        vm.assume(destination != swapper);
        vm.assume(token.balanceOf(destination) == 0);
        vm.assume(non_solver != solver);

        token.mint(swapper, 1e18);
        vm.prank(swapper);
        token.approve(address(theCompact), type(uint256).max);

        vm.prank(swapper);
        uint256 amount = 1e18 / 10;
        uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, amount];
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
            remoteOracle: bytes32(uint256(uint160(address(alwaysYesOracle)))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(
            swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order)
        );

        bytes memory signature = abi.encode(sponsorSig, hex"");

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Other callers are disallowed:

        vm.prank(non_solver);

        vm.expectRevert(abi.encodeWithSignature("NotOrderOwner()"));
        compactSettler.finaliseTo(
            order,
            signature,
            timestamps,
            bytes32(uint256(uint160((solver)))),
            bytes32(uint256(uint160(destination))),
            hex""
        );

        assertEq(token.balanceOf(destination), 0);

        vm.prank(solver);
        compactSettler.finaliseTo(
            order,
            signature,
            timestamps,
            bytes32(uint256(uint160((solver)))),
            bytes32(uint256(uint160(destination))),
            hex""
        );
        vm.snapshotGasLastCall("CompactFinaliseTo");

        assertEq(token.balanceOf(destination), amount);
    }

    function test_finalise_for(address non_solver, address destination) external {
        vm.assume(destination != address(compactSettler));
        vm.assume(destination != address(theCompact));
        vm.assume(destination != address(swapper));
        vm.assume(destination != address(solver));
        vm.assume(non_solver != solver);

        token.mint(swapper, 1e18);
        vm.prank(swapper);
        token.approve(address(theCompact), type(uint256).max);

        vm.prank(swapper);
        uint256 amount = 1e18 / 10;
        uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, amount];
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
            remoteOracle: bytes32(uint256(uint160(address(alwaysYesOracle)))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        bytes memory signature;
        {
            // Make Compact
            uint256[2][] memory idsAndAmounts = new uint256[2][](1);
            idsAndAmounts[0] = [tokenId, amount];

            bytes memory sponsorSig = getCompactBatchWitnessSignature(
                swapperPrivateKey,
                address(compactSettler),
                swapper,
                0,
                type(uint32).max,
                idsAndAmounts,
                witnessHash(order)
            );
            signature = abi.encode(sponsorSig, hex"");
        }
        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Other callers are disallowed:

        bytes memory orderOwnerSignature = hex"";

        vm.prank(non_solver);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        compactSettler.finaliseFor(
            order,
            signature,
            timestamps,
            bytes32(uint256(uint160((solver)))),
            bytes32(uint256(uint160(destination))),
            hex"",
            orderOwnerSignature
        );

        assertEq(token.balanceOf(destination), 0);

        orderOwnerSignature = this.getOrderOpenSignature(
            solverPrivateKey, compactSettler.orderIdentifier(order), bytes32(uint256(uint160(destination))), hex""
        );

        vm.prank(non_solver);
        compactSettler.finaliseFor(
            order,
            signature,
            timestamps,
            bytes32(uint256(uint160((solver)))),
            bytes32(uint256(uint160(destination))),
            hex"",
            orderOwnerSignature
        );
        vm.snapshotGasLastCall("CompactFinaliseFor");

        assertEq(token.balanceOf(destination), amount);
    }

    // --- Fee tests --- //

    function test_invalid_governance_fee(
    ) public {
        vm.prank(owner);
        compactSettler.setGovernanceFee(MAX_GOVERNANCE_FEE);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        compactSettler.setGovernanceFee(MAX_GOVERNANCE_FEE+1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        compactSettler.setGovernanceFee(MAX_GOVERNANCE_FEE + 123123123);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        compactSettler.setGovernanceFee(type(uint64).max);
    }

    function test_governance_fee_change_not_ready(uint64 fee, uint256 timeDelay) public {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.assume(timeDelay < uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);

        vm.prank(owner);
        vm.expectEmit();
        emit NextGovernanceFee(fee, uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);
        compactSettler.setGovernanceFee(fee);

        vm.warp(timeDelay);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeChangeNotReady()"));
        compactSettler.applyGovernanceFee();

        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);

        assertEq(compactSettler.governanceFee(), 0);

        vm.expectEmit();
        emit GovernanceFeeChanged(0, fee);
        compactSettler.applyGovernanceFee();

        assertEq(compactSettler.governanceFee(), fee);
    }

    function test_finalise_self_with_fee(
        uint64 fee
    ) external {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.prank(owner);
        compactSettler.setGovernanceFee(fee);
        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);
        compactSettler.applyGovernanceFee();

        uint256 amount = 1e18 / 10;

        token.mint(swapper, amount);
        vm.prank(swapper);
        token.approve(address(theCompact), type(uint256).max);

        vm.prank(swapper);
        uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, amount];
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
            remoteOracle: bytes32(uint256(uint160(address(alwaysYesOracle)))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(
            swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order)
        );

        bytes memory signature = abi.encode(sponsorSig, hex"");

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        uint256 govFeeAmount = amount * fee / 10 ** 18;
        uint256 amountPostFee = amount - govFeeAmount;

        vm.prank(solver);
        compactSettler.finaliseSelf(order, signature, timestamps, bytes32(uint256(uint160((solver)))));
        vm.snapshotGasLastCall("CompactFinaliseSelfWithFee");

        assertEq(token.balanceOf(solver), amountPostFee);
        assertEq(theCompact.balanceOf(owner, tokenId), govFeeAmount);
    }
}
