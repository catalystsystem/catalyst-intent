// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { Settler7683TestBase } from "./Settler7683.base.t.sol";
import { Settler7683 } from "src/settlers/7683/Settler7683.sol";

import { GaslessCrossChainOrder, OnchainCrossChainOrder } from "src/interfaces/IERC7683.sol";

import { MandateERC7683 } from "src/settlers/7683/Order7683Type.sol";
import { CatalystCompactOrder } from "src/settlers/compact/TheCompactOrderType.sol";
import { OutputDescription, OutputDescriptionType } from "src/settlers/types/OutputDescriptionType.sol";

import { OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

contract Settler7683Test is Settler7683TestBase {
    struct OrderFulfillmentDescription {
        uint32 timestamp;
        OutputDescription outputDescription;
    }

    function test_on_chain_order_identifier() external {
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
            remoteOracle: bytes32(0),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: 2e18,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), 1e18];

        MandateERC7683 memory mandate =
            MandateERC7683({ expiry: type(uint32).max, localOracle: address(0), inputs: inputs, outputs: outputs });

        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: type(uint32).max,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate)
        });

        // Generate the CatalystCompactOrder so we can make the finalise call
        CatalystCompactOrder memory compactOrder = CatalystCompactOrder({
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            expires: mandate.expiry,
            fillDeadline: order.fillDeadline,
            localOracle: mandate.localOracle,
            inputs: mandate.inputs,
            outputs: mandate.outputs
        });

        bytes32 compactOrderId = settler7683.orderIdentifier(compactOrder);
        bytes32 badOnChainOrderId = settler7683.orderIdentifier(order);
        vm.prank(swapper);
        bytes32 goodOnChainOrderId = settler7683.orderIdentifier(order);

        assertEq(compactOrderId, goodOnChainOrderId);
        assertNotEq(compactOrderId, badOnChainOrderId);

        compactOrder.user = address(this);
        bytes32 thisOnChainOrderId = settler7683.orderIdentifier(order);
        assertEq(badOnChainOrderId, thisOnChainOrderId);
        assertNotEq(thisOnChainOrderId, goodOnChainOrderId);
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
        settler7683.validateFills(address(this), orderId, outputDescriptions);
    }

    /// forge-config: default.isolate = true
    function test_validate_fills_one_solver_gas() external {
        OrderFulfillmentDescription[] memory fds = new OrderFulfillmentDescription[](2);
        fds[0] = OrderFulfillmentDescription({
            timestamp: 10001,
            outputDescription: OutputDescription({
                remoteOracle: keccak256(bytes("remoteOracle")),
                remoteFiller: keccak256(bytes("remoteFiller")),
                chainId: 123,
                token: keccak256(bytes("token")),
                amount: 10**18,
                recipient: keccak256(bytes("recipient")),
                remoteCall: hex"",
                fulfillmentContext: hex""
            })
        });
        fds[1] = OrderFulfillmentDescription({
            timestamp: 10001,
            outputDescription: OutputDescription({
                remoteOracle: keccak256(bytes("remoteOracle")),
                remoteFiller: keccak256(bytes("remoteFiller")),
                chainId: 321,
                token: keccak256(bytes("token1")),
                amount: 10**12,
                recipient: keccak256(bytes("recipient")),
                remoteCall: hex"",
                fulfillmentContext: hex""
            })
        });

        test_validate_fills_one_solver(keccak256(bytes("solverIdentifier")), keccak256(bytes("orderId")), fds);
    }

    function test_validate_fills_one_solver(
        bytes32 solverIdentifier,
        bytes32 orderId,
        OrderFulfillmentDescription[] memory orderFulfillmentDescription
    ) public {
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

        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: address(0), // not used
            nonce: 0, // not used
            originChainId: 0, // not used.
            expires: 0, // not used
            fillDeadline: type(uint32).max,
            localOracle: address(this),
            inputs: new uint256[2][](0), // not used
            outputs: outputDescriptions
        });

        settler7683.validateFills(
            order, orderId, solverIdentifier, timestamps
        );
        vm.snapshotGasLastCall("settler", "7683Validate2Fills");
    }

    struct OrderFulfillmentDescriptionWithSolver {
        uint32 timestamp;
        bytes32 solver;
        OutputDescription outputDescription;
    }

    /// forge-config: default.isolate = true
    function test_validate_fills_multiple_solvers_gas() external {
        OrderFulfillmentDescriptionWithSolver[] memory fds = new OrderFulfillmentDescriptionWithSolver[](2);
        fds[0] = OrderFulfillmentDescriptionWithSolver({
            timestamp: 10001,
            solver: keccak256(bytes("solverIdentifier1")),
            outputDescription: OutputDescription({
                remoteOracle: keccak256(bytes("remoteOracle")),
                remoteFiller: keccak256(bytes("remoteFiller")),
                chainId: 123,
                token: keccak256(bytes("token")),
                amount: 10**18,
                recipient: keccak256(bytes("recipient")),
                remoteCall: hex"",
                fulfillmentContext: hex""
            })
        });
        fds[1] = OrderFulfillmentDescriptionWithSolver({
            timestamp: 10001,
            solver: keccak256(bytes("solverIdentifier2")),
            outputDescription: OutputDescription({
                remoteOracle: keccak256(bytes("remoteOracle")),
                remoteFiller: keccak256(bytes("remoteFiller")),
                chainId: 321,
                token: keccak256(bytes("token1")),
                amount: 10**12,
                recipient: keccak256(bytes("recipient")),
                remoteCall: hex"",
                fulfillmentContext: hex""
            })
        });

        test_validate_fills_multiple_solvers(keccak256(bytes("orderId")), fds);
    }

    function test_validate_fills_multiple_solvers(
        bytes32 orderId,
        OrderFulfillmentDescriptionWithSolver[] memory orderFulfillmentDescriptionWithSolver
    ) public {
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
                    OutputEncodingLib.encodeFillDescriptionM(solvers[i], orderId, timestamps[i],
    outputDescriptions[i])
                )
            );
        }
        _validProofSeries[expectedProofPayload] = true;

        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: address(0), // not used
            nonce: 0, // not used
            originChainId: 0, // not used.
            expires: 0, // not used
            fillDeadline: type(uint32).max,
            localOracle: address(this),
            inputs: new uint256[2][](0), // not used
            outputs: outputDescriptions
        });

        settler7683.validateFills(order, orderId, solvers, timestamps);
        vm.snapshotGasLastCall("settler", "7683Validate2FillsMultipleSolvers");
    }

    /// forge-config: default.isolate = true
    function test_open_gas() external {
        test_open(10000, 10**18, makeAddr("user"));
    }

    function test_open(uint32 fillDeadline, uint128 amount, address user) public {
        vm.assume(fillDeadline > block.timestamp);
        vm.assume(token.balanceOf(user) == 0);
        vm.assume(user != address(settler7683));

        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(settler7683), amount);

        OutputDescription[] memory outputs = new OutputDescription[](0);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        MandateERC7683 memory mandate =
            MandateERC7683({ expiry: type(uint32).max, localOracle: address(0), inputs: inputs, outputs: outputs });

        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate)
        });

        assertEq(token.balanceOf(address(user)), amount);

        vm.prank(user);
        settler7683.open(order);
        vm.snapshotGasLastCall("settler", "7683open");

        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(settler7683)), amount);
    }

    /// forge-config: default.isolate = true
    function test_open_for_gas() external {
        test_open_for(10**18, 251251);
    }

    function test_open_for(uint128 amountMint, uint256 nonce) public {
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

        MandateERC7683 memory mandate =
            MandateERC7683({ expiry: type(uint32).max, localOracle: address(0), inputs: inputs, outputs: outputs });

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
        vm.snapshotGasLastCall("settler", "7683openFor");

        assertEq(token.balanceOf(address(swapper)), 0);
        assertEq(token.balanceOf(address(settler7683)), amount);
    }

    /// forge-config: default.isolate = true
    function test_open_for_and_finalise_gas() external {
        test_open_for_and_finalise(10**18, 2512511, hex"");
    }

    function test_open_for_and_finalise(uint128 amountMint, uint256 nonce, bytes memory cdat) public {
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

        MandateERC7683 memory mandate =
            MandateERC7683({ expiry: type(uint32).max, localOracle: alwaysYesOracle, inputs: inputs, outputs: outputs });

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
        vm.snapshotGasLastCall("settler", "7683openForAndFinalise");

        assertEq(token.balanceOf(address(this)), amount);
        assertEq(token.balanceOf(address(settler7683)), 0);
    }

    // -- Larger Integration tests -- //

    /// forge-config: default.isolate = true
    function test_finalise_self_gas() public {
        test_finalise_self(makeAddr("non_solver"));
    }

    function test_finalise_self(
        address non_solver
    ) public {
        vm.assume(non_solver != solver);

        uint256 amount = 1e18 / 10;
        address localOracle = address(alwaysYesOracle);

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
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        MandateERC7683 memory mandate =
            MandateERC7683({ expiry: type(uint32).max, localOracle: localOracle, inputs: inputs, outputs: outputs });

        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: type(uint32).max,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate)
        });

        // Deposit into the escrow
        vm.prank(swapper);
        token.approve(address(settler7683), amount);
        vm.prank(swapper);
        settler7683.open(order);

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Generate the CatalystCompactOrder so we can make the finalise call
        CatalystCompactOrder memory compactOrder = CatalystCompactOrder({
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            expires: mandate.expiry,
            fillDeadline: order.fillDeadline,
            localOracle: mandate.localOracle,
            inputs: mandate.inputs,
            outputs: mandate.outputs
        });

        // Other callers are disallowed:
        vm.prank(non_solver);

        vm.expectRevert(abi.encodeWithSignature("NotOrderOwner()"));
        settler7683.finaliseSelf(compactOrder, timestamps, bytes32(uint256(uint160((solver)))));

        assertEq(token.balanceOf(solver), 0);

        bytes32 orderId = settler7683.orderIdentifier(compactOrder);
        bytes memory payload = OutputEncodingLib.encodeFillDescriptionM(
            bytes32(uint256(uint160((solver)))), orderId, uint32(block.timestamp), outputs[0]
        );
        bytes32 payloadHash = keccak256(payload);

        vm.expectCall(
            address(alwaysYesOracle),
            abi.encodeWithSignature(
                "efficientRequireProven(bytes)",
                abi.encodePacked(
                    mandate.outputs[0].chainId,
                    mandate.outputs[0].remoteOracle,
                    mandate.outputs[0].remoteFiller,
                    payloadHash
                )
            )
        );

        vm.prank(solver);
        settler7683.finaliseSelf(compactOrder, timestamps, bytes32(uint256(uint160((solver)))));
        vm.snapshotGasLastCall("settler", "7683FinaliseSelf");

        assertEq(token.balanceOf(solver), amount);
    }

    function test_revert_finalise_self_too_late(address non_solver, uint32 fillDeadline, uint32 filledAt) external {
        vm.assume(non_solver != solver);
        vm.assume(fillDeadline < filledAt);
        vm.assume(block.timestamp < fillDeadline);

        uint256 amount = 1e18 / 10;

        address localOracle = address(alwaysYesOracle);

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
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        MandateERC7683 memory mandate =
            MandateERC7683({ expiry: type(uint32).max, localOracle: address(0), inputs: inputs, outputs: outputs });

        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate)
        });

        // Deposit into the escrow
        vm.prank(swapper);
        token.approve(address(settler7683), amount);
        vm.prank(swapper);
        settler7683.open(order);

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = filledAt;

        CatalystCompactOrder memory compactOrder = CatalystCompactOrder({
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            expires: mandate.expiry,
            fillDeadline: order.fillDeadline,
            localOracle: mandate.localOracle,
            inputs: mandate.inputs,
            outputs: mandate.outputs
        });

        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSignature("FilledTooLate(uint32,uint32)", fillDeadline, filledAt));
        settler7683.finaliseSelf(compactOrder, timestamps, bytes32(uint256(uint160(solver))));
    }

    /// forge-config: default.isolate = true
    function test_finalise_to_gas() external {
        test_finalise_to(makeAddr("destination"));
    }

    function test_finalise_to(
        address destination
    ) public {
        vm.assume(token.balanceOf(destination) == 0);

        uint256 amount = 1e18 / 10;
        address localOracle = address(alwaysYesOracle);

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
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        MandateERC7683 memory mandate =
            MandateERC7683({ expiry: type(uint32).max, localOracle: localOracle, inputs: inputs, outputs: outputs });

        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: type(uint32).max,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate)
        });

        // Deposit into the escrow
        vm.prank(swapper);
        token.approve(address(settler7683), amount);
        vm.prank(swapper);
        settler7683.open(order);

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Generate the CatalystCompactOrder so we can make the finalise call
        CatalystCompactOrder memory compactOrder = CatalystCompactOrder({
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            expires: mandate.expiry,
            fillDeadline: order.fillDeadline,
            localOracle: mandate.localOracle,
            inputs: mandate.inputs,
            outputs: mandate.outputs
        });

        {
            bytes32 orderId = settler7683.orderIdentifier(compactOrder);
            bytes memory payload = OutputEncodingLib.encodeFillDescriptionM(
                bytes32(uint256(uint160((solver)))), orderId, uint32(block.timestamp), outputs[0]
            );
            bytes32 payloadHash = keccak256(payload);

            vm.expectCall(
                address(alwaysYesOracle),
                abi.encodeWithSignature(
                    "efficientRequireProven(bytes)",
                    abi.encodePacked(
                        mandate.outputs[0].chainId,
                        mandate.outputs[0].remoteOracle,
                        mandate.outputs[0].remoteFiller,
                        payloadHash
                    )
                )
            );
        }
        vm.prank(solver);
        settler7683.finaliseTo(
            compactOrder,
            timestamps,
            bytes32(uint256(uint160((solver)))),
            bytes32(uint256(uint160((destination)))),
            hex""
        );
        vm.snapshotGasLastCall("settler", "7683FinaliseTo");

        assertEq(token.balanceOf(destination), amount);
    }

    /// forge-config: default.isolate = true
    function test_finalise_for_gas() external {
        test_finalise_for(makeAddr("destination"), makeAddr("caller"));
    }

    function test_finalise_for(address destination, address caller) public {
        vm.assume(token.balanceOf(destination) == 0);

        uint256 amount = 1e18 / 10;

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
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        MandateERC7683 memory mandate = MandateERC7683({
            expiry: type(uint32).max,
            localOracle: address(alwaysYesOracle),
            inputs: inputs,
            outputs: outputs
        });

        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: type(uint32).max,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate)
        });

        // Deposit into the escrow
        vm.prank(swapper);
        token.approve(address(settler7683), amount);
        vm.prank(swapper);
        settler7683.open(order);

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Generate the CatalystCompactOrder so we can make the finalise call
        CatalystCompactOrder memory compactOrder = CatalystCompactOrder({
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            expires: mandate.expiry,
            fillDeadline: order.fillDeadline,
            localOracle: mandate.localOracle,
            inputs: mandate.inputs,
            outputs: mandate.outputs
        });

        bytes32 orderId = settler7683.orderIdentifier(compactOrder);

        bytes memory orderOwnerSignature =
            this.getOrderOpenSignature(solverPrivateKey, orderId, bytes32(uint256(uint160(destination))), hex"");
        {
            bytes memory payload = OutputEncodingLib.encodeFillDescriptionM(
                bytes32(uint256(uint160((solver)))), orderId, uint32(block.timestamp), outputs[0]
            );
            bytes32 payloadHash = keccak256(payload);

            vm.expectCall(
                address(alwaysYesOracle),
                abi.encodeWithSignature(
                    "efficientRequireProven(bytes)",
                    abi.encodePacked(
                        mandate.outputs[0].chainId,
                        mandate.outputs[0].remoteOracle,
                        mandate.outputs[0].remoteFiller,
                        payloadHash
                    )
                )
            );
        }
        vm.prank(caller);
        settler7683.finaliseFor(
            compactOrder,
            timestamps,
            bytes32(uint256(uint160((solver)))),
            bytes32(uint256(uint160((destination)))),
            hex"",
            orderOwnerSignature
        );
        vm.snapshotGasLastCall("settler", "7683FinaliseFor");

        assertEq(token.balanceOf(destination), amount);
    }

    // --- Fee tests --- //

    function test_invalid_governance_fee() public {
        vm.prank(owner);
        settler7683.setGovernanceFee(MAX_GOVERNANCE_FEE);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        settler7683.setGovernanceFee(MAX_GOVERNANCE_FEE + 1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        settler7683.setGovernanceFee(MAX_GOVERNANCE_FEE + 123123123);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        settler7683.setGovernanceFee(type(uint64).max);
    }

    function test_governance_fee_change_not_ready(uint64 fee, uint256 timeDelay) public {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.assume(timeDelay < uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);

        vm.prank(owner);
        vm.expectEmit();
        emit NextGovernanceFee(fee, uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);
        settler7683.setGovernanceFee(fee);

        vm.warp(timeDelay);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeChangeNotReady()"));
        settler7683.applyGovernanceFee();

        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);

        assertEq(settler7683.governanceFee(), 0);

        vm.expectEmit();
        emit GovernanceFeeChanged(0, fee);
        settler7683.applyGovernanceFee();

        assertEq(settler7683.governanceFee(), fee);
    }

    /// forge-config: default.isolate = true
    function test_finalise_self_with_fee_gas() public {
        test_finalise_self_with_fee(MAX_GOVERNANCE_FEE / 3);
    }

    function test_finalise_self_with_fee(
        uint64 fee
    ) public {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.prank(owner);
        settler7683.setGovernanceFee(fee);
        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);
        settler7683.applyGovernanceFee();

        uint256 amount = 1e18 / 10;
        address localOracle = address(alwaysYesOracle);

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
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        MandateERC7683 memory mandate =
            MandateERC7683({ expiry: type(uint32).max, localOracle: localOracle, inputs: inputs, outputs: outputs });

        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: type(uint32).max,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate)
        });

        // Deposit into the escrow
        vm.prank(swapper);
        token.approve(address(settler7683), amount);
        vm.prank(swapper);
        settler7683.open(order);

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Generate the CatalystCompactOrder so we can make the finalise call
        CatalystCompactOrder memory compactOrder = CatalystCompactOrder({
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            expires: mandate.expiry,
            fillDeadline: order.fillDeadline,
            localOracle: mandate.localOracle,
            inputs: mandate.inputs,
            outputs: mandate.outputs
        });

        bytes32 orderId = settler7683.orderIdentifier(compactOrder);
        bytes memory payload = OutputEncodingLib.encodeFillDescriptionM(
            bytes32(uint256(uint160((solver)))), orderId, uint32(block.timestamp), outputs[0]
        );
        bytes32 payloadHash = keccak256(payload);

        vm.expectCall(
            address(alwaysYesOracle),
            abi.encodeWithSignature(
                "efficientRequireProven(bytes)",
                abi.encodePacked(
                    mandate.outputs[0].chainId,
                    mandate.outputs[0].remoteOracle,
                    mandate.outputs[0].remoteFiller,
                    payloadHash
                )
            )
        );

        vm.prank(solver);
        settler7683.finaliseSelf(compactOrder, timestamps, bytes32(uint256(uint160((solver)))));
        vm.snapshotGasLastCall("settler", "7683FinaliseSelfWithFee");

        uint256 govFeeAmount = amount * fee / 10 ** 18;
        uint256 amountPostFee = amount - govFeeAmount;

        assertEq(token.balanceOf(solver), amountPostFee);
        assertEq(token.balanceOf(settler7683.owner()), govFeeAmount);
    }
}
