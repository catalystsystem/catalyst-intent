// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { TestERC7683Base } from "./TestERC7683Base.t.sol";
import { Settler7683 } from "src/settlers/7683/Settler7683.sol";

import { GaslessCrossChainOrder, OnchainCrossChainOrder } from "src/interfaces/IERC7683.sol";

import { AllowOpenType } from "src/settlers/types/AllowOpenType.sol";
import { OrderPurchase, OrderPurchaseType } from "src/settlers/types/OrderPurchaseType.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

import { CatalystCompactOrder } from "src/settlers/compact/TheCompactOrderType.sol";
import { MandateERC7683 } from "src/settlers/7683/Order7683Type.sol";
import { OutputDescription, OutputDescriptionType } from "src/settlers/types/OutputDescriptionType.sol";

import { MessageEncodingLib } from "src/libs/MessageEncodingLib.sol";
import { OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

import { AlwaysOKAllocator } from "the-compact/src/test/AlwaysOKAllocator.sol";

contract TestERC20Settler is TestERC7683Base {

    struct OrderFulfillmentDescription {
        uint32 timestamp;
        OutputDescription outputDescription;
    }

    function test_validate_fills_now(
        bytes32 orderId,
        address callerOfContract,
        OrderFulfillmentDescription[] calldata orderFulfillmentDescription
    ) external {
        vm.assume(orderFulfillmentDescription.length > 0);

        bytes memory expectedProofPayload = hex"";
        uint32[] memory timestamps = new uint32[](orderFulfillmentDescription.length);
        OutputDescription[] memory outputDescriptions = new OutputDescription[](orderFulfillmentDescription.length);
        for (uint256 i; i < orderFulfillmentDescription.length; ++i) {
            timestamps[i] = orderFulfillmentDescription[i].timestamp;
            outputDescriptions[i] = orderFulfillmentDescription[i].outputDescription;
            OutputDescription memory output = outputDescriptions[i];

            expectedProofPayload = abi.encodePacked(
                expectedProofPayload,
                output.chainId,
                output.remoteOracle,
                output.remoteFiller,
                keccak256(
                    OutputEncodingLib.encodeFillDescription(
                        bytes32(uint256(uint160(callerOfContract))),
                        orderId,
                        uint32(block.timestamp),
                        output.token,
                        output.amount,
                        output.recipient,
                        output.remoteCall,
                        output.fulfillmentContext
                    )
                )
            );
        }
        _validProofSeries[expectedProofPayload] = true;

        vm.prank(callerOfContract);
        settler7683.validateFills(
            address(this),
            orderId,
            outputDescriptions
        );
    }

    function test_validate_fills_one_solver(
        bytes32 solverIdentifier,
        bytes32 orderId,
        OrderFulfillmentDescription[] calldata orderFulfillmentDescription
    ) external {
        vm.assume(orderFulfillmentDescription.length > 0);

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

        settler7683.validateFills(
            address(this),
            orderId,
            solverIdentifier,
            timestamps,
            outputDescriptions
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

        settler7683.validateFills(
            address(this),
            orderId,
            solvers,
            timestamps,
            outputDescriptions
        );
    }

    function test_open(
        uint32 fillDeadline,
        uint128 amount,
        address user
    ) external {
        vm.assume(fillDeadline > block.timestamp);
        vm.assume(token.balanceOf(user) == 0);

        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(settler7683), amount);

        OutputDescription[] memory outputs = new OutputDescription[](0);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        MandateERC7683 memory mandate = MandateERC7683({
            expiry: type(uint32).max,
            localOracle: address(0),
            inputs: inputs,
            outputs: outputs
        });

        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate)
        });

        assertEq(token.balanceOf(address(user)), amount);

        vm.prank(user);
        settler7683.open(order);

        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(settler7683)), amount);
    }

    function test_open_for(
        uint128 amountMint,
        uint256 nonce
    ) external {
        token.mint(swapper, amountMint);

        uint256 amount = token.balanceOf(swapper);
        uint256 originChainId = block.chainid;
        uint32 openDeadline = type(uint32).max;
        uint32 fillDeadline = type(uint32).max;
        bytes32 orderDataType = bytes32(0);


        vm.prank(swapper);
        token.approve(address(permit2), amount);

        OutputDescription[] memory outputs = new OutputDescription[](0);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        MandateERC7683 memory mandate = MandateERC7683({
            expiry: type(uint32).max,
            localOracle: address(0),
            inputs: inputs,
            outputs: outputs
        });

        GaslessCrossChainOrder memory order = GaslessCrossChainOrder({
            originSettler: address(settler7683),
            user: swapper,
            nonce: nonce,
            originChainId: originChainId,
            openDeadline: openDeadline,
            fillDeadline: fillDeadline,
            orderDataType: orderDataType,
            orderData: abi.encode(mandate)
        });
        
        bytes memory signature = getPermit2Signature(swapperPrivateKey, order);

        assertEq(token.balanceOf(address(swapper)), amount);

        vm.prank(swapper);
        settler7683.openFor(order, signature, hex"");

        assertEq(token.balanceOf(address(swapper)), 0);
        assertEq(token.balanceOf(address(settler7683)), amount);
    }

    function test_open_for_and_finalise(
        uint128 amountMint,
        uint256 nonce,
        bytes calldata cdat
    ) external {
        token.mint(swapper, amountMint);

        uint256 amount = token.balanceOf(swapper);
        uint256 originChainId = block.chainid;
        uint32 openDeadline = type(uint32).max;
        uint32 fillDeadline = type(uint32).max;
        bytes32 orderDataType = bytes32(0);


        vm.prank(swapper);
        token.approve(address(permit2), amount);

        OutputDescription[] memory outputs = new OutputDescription[](0);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        MandateERC7683 memory mandate = MandateERC7683({
            expiry: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        GaslessCrossChainOrder memory order = GaslessCrossChainOrder({
            originSettler: address(settler7683),
            user: swapper,
            nonce: nonce,
            originChainId: originChainId,
            openDeadline: openDeadline,
            fillDeadline: fillDeadline,
            orderDataType: orderDataType,
            orderData: abi.encode(mandate)
        });
        
        bytes memory signature = getPermit2Signature(swapperPrivateKey, order);

        assertEq(token.balanceOf(address(swapper)), amount);

        expectedCalldata = cdat;

        vm.prank(swapper);
        settler7683.openForAndFinalise(order, signature, address(this), cdat);

        assertEq(token.balanceOf(address(this)), amount);
        assertEq(token.balanceOf(address(settler7683)), 0);
    }

    // -- Larger Integration tests -- //

    // function test_finalise_self(
    //     address non_solver
    // ) external {
    //     vm.assume(non_solver != solver);

    //     vm.prank(swapper);
    //     uint256 amount = 1e18 / 10;
    //     uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

    //     address localOracle = address(alwaysYesOracle);

    //     uint256[2][] memory inputs = new uint256[2][](1);
    //     inputs[0] = [tokenId, amount];
    //     OutputDescription[] memory outputs = new OutputDescription[](1);
    //     outputs[0] = OutputDescription({
    //         remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
    //         remoteOracle: bytes32(uint256(uint160(localOracle))),
    //         chainId: block.chainid,
    //         token: bytes32(uint256(uint160(address(anotherToken)))),
    //         amount: amount,
    //         recipient: bytes32(uint256(uint160(swapper))),
    //         remoteCall: hex"",
    //         fulfillmentContext: hex""
    //     });
    //     CatalystCompactOrder memory order = CatalystCompactOrder({
    //         user: address(swapper),
    //         nonce: 0,
    //         originChainId: block.chainid,
    //         fillDeadline: type(uint32).max,
    //         expires: type(uint32).max,
    //         localOracle: alwaysYesOracle,
    //         inputs: inputs,
    //         outputs: outputs
    //     });

    //     // Make Compact
    //     uint256[2][] memory idsAndAmounts = new uint256[2][](1);
    //     idsAndAmounts[0] = [tokenId, amount];

    //     bytes memory sponsorSig = getCompactBatchWitnessSignature(
    //         swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order)
    //     );
    //     bytes memory allocatorSig = hex"";

    //     bytes memory signature = abi.encode(sponsorSig, allocatorSig);

    //     bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

    //     bytes32 orderId = compactSettler.orderIdentifier(order);

    //     bytes memory payload =
    //         OutputEncodingLib.encodeFillDescriptionM(solverIdentifier, orderId, uint32(block.timestamp), outputs[0]);
    //     bytes32 payloadHash = keccak256(payload);

    //     uint32[] memory timestamps = new uint32[](1);
    //     timestamps[0] = uint32(block.timestamp);

    //     // Other callers are disallowed:

    //     vm.prank(non_solver);

    //     vm.expectRevert(abi.encodeWithSignature("NotOrderOwner()"));
    //     compactSettler.finaliseSelf(order, signature, timestamps, solverIdentifier);

    //     assertEq(token.balanceOf(solver), 0);

    //     vm.expectCall(
    //         address(alwaysYesOracle),
    //         abi.encodeWithSignature(
    //             "efficientRequireProven(bytes)",
    //             abi.encodePacked(
    //                 order.outputs[0].chainId, order.outputs[0].remoteOracle, order.outputs[0].remoteFiller, payloadHash
    //             )
    //         )
    //     );

    //     vm.prank(solver);
    //     compactSettler.finaliseSelf(order, signature, timestamps, solverIdentifier);
    //     vm.snapshotGasLastCall("finaliseSelf");

    //     assertEq(token.balanceOf(solver), amount);
    // }

    // function test_revert_finalise_self_too_late(address non_solver, uint32 fillDeadline, uint32 filledAt) external {
    //     vm.assume(non_solver != solver);
    //     vm.assume(fillDeadline < filledAt);

    //     vm.prank(swapper);
    //     uint256 amount = 1e18 / 10;
    //     uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

    //     address localOracle = address(alwaysYesOracle);

    //     uint256[2][] memory inputs = new uint256[2][](1);
    //     inputs[0] = [tokenId, amount];
    //     OutputDescription[] memory outputs = new OutputDescription[](1);
    //     outputs[0] = OutputDescription({
    //         remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
    //         remoteOracle: bytes32(uint256(uint160(localOracle))),
    //         chainId: block.chainid,
    //         token: bytes32(uint256(uint160(address(anotherToken)))),
    //         amount: amount,
    //         recipient: bytes32(uint256(uint160(swapper))),
    //         remoteCall: hex"",
    //         fulfillmentContext: hex""
    //     });
    //     CatalystCompactOrder memory order = CatalystCompactOrder({
    //         user: address(swapper),
    //         nonce: 0,
    //         originChainId: block.chainid,
    //         fillDeadline: fillDeadline,
    //         expires: type(uint32).max,
    //         localOracle: alwaysYesOracle,
    //         inputs: inputs,
    //         outputs: outputs
    //     });

    //     // Make Compact
    //     uint256[2][] memory idsAndAmounts = new uint256[2][](1);
    //     idsAndAmounts[0] = [tokenId, amount];

    //     bytes memory sponsorSig = getCompactBatchWitnessSignature(
    //         swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order)
    //     );
    //     bytes memory allocatorSig = hex"";

    //     bytes memory signature = abi.encode(sponsorSig, allocatorSig);

    //     bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

    //     uint32[] memory timestamps = new uint32[](1);
    //     timestamps[0] = filledAt;

    //     vm.prank(solver);
    //     vm.expectRevert(abi.encodeWithSignature("FilledTooLate(uint32,uint32)", fillDeadline, filledAt));
    //     compactSettler.finaliseSelf(order, signature, timestamps, solverIdentifier);
    // }

    // function test_finalise_to(address non_solver, address destination) external {
    //     vm.assume(destination != address(compactSettler));
    //     vm.assume(destination != address(theCompact));
    //     vm.assume(token.balanceOf(destination) == 0);
    //     vm.assume(non_solver != solver);

    //     vm.prank(swapper);
    //     uint256 amount = 1e18 / 10;
    //     uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

    //     address localOracle = address(alwaysYesOracle);

    //     uint256[2][] memory inputs = new uint256[2][](1);
    //     inputs[0] = [tokenId, amount];
    //     OutputDescription[] memory outputs = new OutputDescription[](1);
    //     outputs[0] = OutputDescription({
    //         remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
    //         remoteOracle: bytes32(uint256(uint160(localOracle))),
    //         chainId: block.chainid,
    //         token: bytes32(uint256(uint160(address(anotherToken)))),
    //         amount: amount,
    //         recipient: bytes32(uint256(uint160(swapper))),
    //         remoteCall: hex"",
    //         fulfillmentContext: hex""
    //     });
    //     CatalystCompactOrder memory order = CatalystCompactOrder({
    //         user: address(swapper),
    //         nonce: 0,
    //         originChainId: block.chainid,
    //         fillDeadline: type(uint32).max,
    //         expires: type(uint32).max,
    //         localOracle: alwaysYesOracle,
    //         inputs: inputs,
    //         outputs: outputs
    //     });

    //     // Make Compact
    //     uint256[2][] memory idsAndAmounts = new uint256[2][](1);
    //     idsAndAmounts[0] = [tokenId, amount];

    //     bytes memory sponsorSig = getCompactBatchWitnessSignature(
    //         swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order)
    //     );
    //     bytes memory allocatorSig = hex"";

    //     bytes memory signature = abi.encode(sponsorSig, allocatorSig);

    //     bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

    //     uint32[] memory timestamps = new uint32[](1);
    //     timestamps[0] = uint32(block.timestamp);

    //     // Other callers are disallowed:

    //     vm.prank(non_solver);

    //     vm.expectRevert(abi.encodeWithSignature("NotOrderOwner()"));
    //     compactSettler.finaliseTo(
    //         order, signature, timestamps, solverIdentifier, bytes32(uint256(uint160(destination))), hex""
    //     );

    //     assertEq(token.balanceOf(destination), 0);

    //     vm.prank(solver);
    //     compactSettler.finaliseTo(
    //         order, signature, timestamps, solverIdentifier, bytes32(uint256(uint160(destination))), hex""
    //     );
    //     vm.snapshotGasLastCall("finaliseTo");

    //     assertEq(token.balanceOf(destination), amount);
    // }

    // function test_finalise_for(address non_solver, address destination) external {
    //     vm.assume(destination != address(compactSettler));
    //     vm.assume(destination != address(theCompact));
    //     vm.assume(destination != address(swapper));
    //     vm.assume(destination != address(solver));
    //     vm.assume(non_solver != solver);

    //     vm.prank(swapper);
    //     uint256 amount = 1e18 / 10;
    //     uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

    //     address localOracle = address(alwaysYesOracle);

    //     uint256[2][] memory inputs = new uint256[2][](1);
    //     inputs[0] = [tokenId, amount];
    //     OutputDescription[] memory outputs = new OutputDescription[](1);
    //     outputs[0] = OutputDescription({
    //         remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
    //         remoteOracle: bytes32(uint256(uint160(localOracle))),
    //         chainId: block.chainid,
    //         token: bytes32(uint256(uint160(address(anotherToken)))),
    //         amount: amount,
    //         recipient: bytes32(uint256(uint160(swapper))),
    //         remoteCall: hex"",
    //         fulfillmentContext: hex""
    //     });
    //     CatalystCompactOrder memory order = CatalystCompactOrder({
    //         user: address(swapper),
    //         nonce: 0,
    //         originChainId: block.chainid,
    //         fillDeadline: type(uint32).max,
    //         expires: type(uint32).max,
    //         localOracle: alwaysYesOracle,
    //         inputs: inputs,
    //         outputs: outputs
    //     });

    //     // Make Compact
    //     uint256[2][] memory idsAndAmounts = new uint256[2][](1);
    //     idsAndAmounts[0] = [tokenId, amount];

    //     bytes memory sponsorSig = getCompactBatchWitnessSignature(
    //         swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order)
    //     );
    //     bytes memory allocatorSig = hex"";

    //     bytes memory signature = abi.encode(sponsorSig, allocatorSig);

    //     bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

    //     bytes32 orderId = compactSettler.orderIdentifier(order);

    //     uint32[] memory timestamps = new uint32[](1);
    //     timestamps[0] = uint32(block.timestamp);

    //     // Other callers are disallowed:

    //     bytes memory orderOwnerSignature = hex"";

    //     vm.prank(non_solver);
    //     vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
    //     compactSettler.finaliseFor(
    //         order,
    //         signature,
    //         timestamps,
    //         solverIdentifier,
    //         bytes32(uint256(uint160(destination))),
    //         hex"",
    //         orderOwnerSignature
    //     );

    //     assertEq(token.balanceOf(destination), 0);

    //     orderOwnerSignature =
    //         this.getOrderOpenSignature(solverPrivateKey, orderId, bytes32(uint256(uint160(destination))), hex"");

    //     vm.prank(non_solver);
    //     compactSettler.finaliseFor(
    //         order,
    //         signature,
    //         timestamps,
    //         solverIdentifier,
    //         bytes32(uint256(uint160(destination))),
    //         hex"",
    //         orderOwnerSignature
    //     );
    //     vm.snapshotGasLastCall("finaliseFor");

    //     assertEq(token.balanceOf(destination), amount);
    // }

    // // --- Fee tests --- //

    // function test_invalid_governance_fee(
    //     uint64 fee
    // ) public {
    //     vm.assume(fee > MAX_GOVERNANCE_FEE);

    //     vm.prank(owner);
    //     vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
    //     compactSettler.setGovernanceFee(fee);
    // }

    // function test_governance_fee_change_not_ready(uint64 fee, uint256 timeDelay) public {
    //     vm.assume(fee <= MAX_GOVERNANCE_FEE);
    //     vm.assume(timeDelay < uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);

    //     vm.prank(owner);
    //     vm.expectEmit();
    //     emit NextGovernanceFee(fee, uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);
    //     compactSettler.setGovernanceFee(fee);

    //     vm.warp(timeDelay);
    //     vm.expectRevert(abi.encodeWithSignature("GovernanceFeeChangeNotReady()"));
    //     compactSettler.applyGovernanceFee();

    //     vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);

    //     assertEq(compactSettler.governanceFee(), 0);

    //     vm.expectEmit();
    //     emit GovernanceFeeChanged(0, fee);
    //     compactSettler.applyGovernanceFee();

    //     assertEq(compactSettler.governanceFee(), fee);
    // }

    // function test_finalise_self_with_fee(
    //     uint64 fee
    // ) external {
    //     vm.assume(fee <= MAX_GOVERNANCE_FEE);
    //     vm.prank(owner);
    //     compactSettler.setGovernanceFee(fee);
    //     vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);
    //     compactSettler.applyGovernanceFee();

    //     vm.prank(swapper);
    //     uint256 amount = 1e18 / 10;
    //     uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

    //     address localOracle = address(alwaysYesOracle);

    //     uint256[2][] memory inputs = new uint256[2][](1);
    //     inputs[0] = [tokenId, amount];
    //     OutputDescription[] memory outputs = new OutputDescription[](1);
    //     outputs[0] = OutputDescription({
    //         remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
    //         remoteOracle: bytes32(uint256(uint160(localOracle))),
    //         chainId: block.chainid,
    //         token: bytes32(uint256(uint160(address(anotherToken)))),
    //         amount: amount,
    //         recipient: bytes32(uint256(uint160(swapper))),
    //         remoteCall: hex"",
    //         fulfillmentContext: hex""
    //     });
    //     CatalystCompactOrder memory order = CatalystCompactOrder({
    //         user: address(swapper),
    //         nonce: 0,
    //         originChainId: block.chainid,
    //         fillDeadline: type(uint32).max,
    //         expires: type(uint32).max,
    //         localOracle: alwaysYesOracle,
    //         inputs: inputs,
    //         outputs: outputs
    //     });

    //     // Make Compact
    //     uint256[2][] memory idsAndAmounts = new uint256[2][](1);
    //     idsAndAmounts[0] = [tokenId, amount];

    //     bytes memory sponsorSig = getCompactBatchWitnessSignature(
    //         swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order)
    //     );
    //     bytes memory allocatorSig = hex"";

    //     bytes memory signature = abi.encode(sponsorSig, allocatorSig);

    //     bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

    //     uint32[] memory timestamps = new uint32[](1);
    //     timestamps[0] = uint32(block.timestamp);

    //     uint256 govFeeAmount = amount * fee / 10 ** 18;
    //     uint256 amountPostFee = amount - govFeeAmount;

    //     vm.prank(solver);
    //     compactSettler.finaliseSelf(order, signature, timestamps, solverIdentifier);
    //     vm.snapshotGasLastCall("finaliseSelf");

    //     assertEq(token.balanceOf(solver), amountPostFee);
    //     assertEq(theCompact.balanceOf(owner, tokenId), govFeeAmount);
    // }
}