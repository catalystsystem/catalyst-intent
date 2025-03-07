// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { CoinFiller } from "src/fillers/coin/CoinFiller.sol";
import { CompactSettlerWithDeposit } from "src/settlers/compact/CompactSettlerWithDeposit.sol";

import { AllowOpenType } from "src/settlers/types/AllowOpenType.sol";
import { OrderPurchaseType } from "src/settlers/types/OrderPurchaseType.sol";

import { AlwaysYesOracle } from "../mocks/AlwaysYesOracle.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

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

contract MockDepositCompactSettler is CompactSettlerWithDeposit {
    constructor(
        address compact
    ) CompactSettlerWithDeposit(compact) { }

    function validateFills(address localOracle, bytes32 orderId, bytes32[] calldata solvers, uint32[] calldata timestamps, OutputDescription[] calldata outputDescriptions) external view {
        _validateFills(localOracle, orderId, solvers, timestamps, outputDescriptions);
    }

    function validateFills(address localOracle, bytes32 orderId, bytes32 solver, uint32[] calldata timestamps, OutputDescription[] calldata outputDescriptions) external view {
        _validateFills(localOracle, orderId, solver, timestamps, outputDescriptions);
    }
}

contract TestCompactSettler is Test {
    event Transfer(address from, address to, uint256 amount);
    event Transfer(address by, address from, address to, uint256 id, uint256 amount);
    event CompactRegistered(address indexed sponsor, bytes32 claimHash, bytes32 typehash, uint256 expires);

    MockDepositCompactSettler compactSettler;
    CoinFiller coinFiller;

    // Oracles
    address alwaysYesOracle;

    uint256 swapperPrivateKey;
    address swapper;
    uint256 solverPrivateKey;
    address solver;
    uint256 testGuardianPrivateKey;
    address testGuardian;

    MockERC20 token;
    MockERC20 anotherToken;

    TheCompact public theCompact;
    address alwaysOKAllocator;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public virtual {
        theCompact = new TheCompact();

        alwaysOKAllocator = address(new AlwaysOKAllocator());

        theCompact.__registerAllocator(alwaysOKAllocator, "");

        DOMAIN_SEPARATOR = EIP712(address(theCompact)).DOMAIN_SEPARATOR();

        compactSettler = new MockDepositCompactSettler(address(theCompact));
        coinFiller = new CoinFiller();
        alwaysYesOracle = address(new AlwaysYesOracle());

        token = new MockERC20("Mock ERC20", "MOCK", 18);
        anotherToken = new MockERC20("Mock2 ERC20", "MOCK2", 18);

        (swapper, swapperPrivateKey) = makeAddrAndKey("swapper");
        (solver, solverPrivateKey) = makeAddrAndKey("solver");

        token.mint(swapper, 1e18);

        anotherToken.mint(solver, 1e18);

        vm.prank(swapper);
        token.approve(address(theCompact), type(uint256).max);
        vm.prank(solver);
        anotherToken.approve(address(coinFiller), type(uint256).max);

        // Oracles
    }

    function orderHash(
        CatalystCompactOrder calldata order
    ) external pure returns (bytes32) {
        return TheCompactOrderType.orderHash(order);
    }

    function compactHash(address arbiter, address sponsor, uint256 nonce, uint256 expires, CatalystCompactOrder calldata order) external pure returns (bytes32) {
        return TheCompactOrderType.compactHash(arbiter, sponsor, nonce, expires, order);
    }

    function getOrderPurchaseSignature(
        uint256 privateKey,
        bytes32 orderId,
        address originSettler,
        address destination,
        bytes calldata call,
        uint64 discount,
        uint32 timeToBuy
    ) external view returns (bytes memory sig) {
        bytes32 domainSeparator = compactSettler.DOMAIN_SEPARATOR();
        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, OrderPurchaseType.hashOrderPurchase(orderId, originSettler, destination, call, discount, timeToBuy)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function getOrderOpenSignature(uint256 privateKey, bytes32 orderId, address originSettler, address destination, bytes calldata call) external view returns (bytes memory sig) {
        bytes32 domainSeparator = compactSettler.DOMAIN_SEPARATOR();
        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, AllowOpenType.hashAllowOpen(orderId, originSettler, destination, call)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function getCompactBatchWitnessSignature(
        uint256 privateKey,
        bytes32 typeHash,
        address arbiter,
        address sponsor,
        uint256 nonce,
        uint256 expires,
        uint256[2][] memory idsAndAmounts,
        bytes32 witness
    ) internal view returns (bytes memory sig) {
        bytes32 domainSeparator = EIP712(address(theCompact)).DOMAIN_SEPARATOR();
        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(typeHash, arbiter, sponsor, nonce, expires, keccak256(abi.encodePacked(idsAndAmounts)), witness))));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function toTokenId(address tkn, Scope scope, ResetPeriod resetPeriod, address allocator) internal pure returns (uint256 id) {
        // Derive the allocator ID for the provided allocator address.
        uint96 allocatorId = IdLib.usingAllocatorId(allocator);

        // Derive resource lock ID (pack scope, reset period, allocator ID, & token).
        id = ((EfficiencyLib.asUint256(scope) << 255) | (EfficiencyLib.asUint256(resetPeriod) << 252) | (EfficiencyLib.asUint256(allocatorId) << 160) | EfficiencyLib.asUint256(tkn));
    }

    function test_deposit_for() external {
        address target = address(uint160(123123123));

        ResetPeriod resetPeriod = ResetPeriod.OneHourAndFiveMinutes;
        Scope scope = Scope.Multichain;

        uint256 tokenId = toTokenId(address(token), scope, resetPeriod, alwaysOKAllocator);
        uint256 amount = 1e18 / 10;

        address localOracle = alwaysYesOracle;

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, amount];
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
            remoteOracle: bytes32(uint256(uint160(localOracle))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(target))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystCompactOrder memory order =
            CatalystCompactOrder({ user: address(target), nonce: 0, originChainId: block.chainid, fillDeadline: type(uint32).max, localOracle: localOracle, inputs: inputs, outputs: outputs });

        vm.prank(swapper);
        token.approve(address(compactSettler), amount);

        bytes32 claimHash = this.compactHash(address(compactSettler), order.user, order.nonce, order.fillDeadline, order);
        bytes32 typehash = 0x3bf5e03b33f9a0f3a5f54719ee043a9f9b34f4de44765c1b5afb7e0de6b8a6b0;

        vm.expectEmit();
        emit CompactRegistered(target, claimHash, typehash, block.timestamp + 65 * 60);

        vm.prank(swapper);
        compactSettler.depositFor(order, resetPeriod);
    }

    function hashOrderPurchase(bytes32 orderId, address originSettler, address destination, bytes calldata call, uint64 discount, uint32 timeToBuy) external pure returns (bytes32) {
        return OrderPurchaseType.hashOrderPurchase(orderId, originSettler, destination, call, discount, timeToBuy);
    }

    function test_purchase_order(address purchaser, address target) external {
        vm.assume(purchaser != address(0));
        vm.assume(target != address(0));
        uint256 amount = 10 ** 18;

        token.mint(purchaser, amount);
        anotherToken.mint(purchaser, amount);

        uint256[2][] memory inputs = new uint256[2][](2);
        inputs[0][0] = uint256(uint160(address(token)));
        inputs[0][1] = amount;
        inputs[1][0] = uint256(uint160(address(anotherToken)));
        inputs[1][1] = amount;
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
            remoteOracle: bytes32(uint256(uint160(alwaysYesOracle))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(target))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystCompactOrder memory order =
            CatalystCompactOrder({ user: address(target), nonce: 0, originChainId: block.chainid, fillDeadline: type(uint32).max, localOracle: alwaysYesOracle, inputs: inputs, outputs: outputs });

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));
        console.logBytes32(orderSolvedByIdentifier);

        bytes32 orderId = compactSettler.orderIdentifier(order);

        uint256 expiryTimestamp = type(uint256).max;
        address newDestination = solver;
        bytes memory call = hex"";
        uint48 discount = 0;
        uint32 timeToBuy = 1000;
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderId, address(compactSettler), newDestination, call, discount, timeToBuy);

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.prank(purchaser);
        token.approve(address(compactSettler), amount);
        vm.prank(purchaser);
        anotherToken.approve(address(compactSettler), amount);

        vm.prank(purchaser);
        compactSettler.purchaseOrder(orderId, order, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);

        (uint32 storageLastOrderTimestamp, address storagePurchaser) = compactSettler.purchasedOrders(orderSolvedByIdentifier, orderId);
        assertEq(storageLastOrderTimestamp, currentTime - timeToBuy);
        assertEq(storagePurchaser, purchaser);
    }

    function test_revert_purchase_order_invalid_order_id(address purchaser, address target) external {
        vm.assume(purchaser != address(0));
        vm.assume(target != address(0));
        uint256 amount = 10 ** 18;

        token.mint(purchaser, amount);
        anotherToken.mint(purchaser, amount);

        uint256[2][] memory inputs = new uint256[2][](2);
        inputs[0][0] = uint256(uint160(address(token)));
        inputs[0][1] = amount;
        inputs[1][0] = uint256(uint160(address(anotherToken)));
        inputs[1][1] = amount;
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
            remoteOracle: bytes32(uint256(uint160(alwaysYesOracle))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(target))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystCompactOrder memory order =
            CatalystCompactOrder({ user: address(target), nonce: 0, originChainId: block.chainid, fillDeadline: type(uint32).max, localOracle: alwaysYesOracle, inputs: inputs, outputs: outputs });

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));
        console.logBytes32(orderSolvedByIdentifier);

        bytes32 orderId = compactSettler.orderIdentifier(order);

        uint256 expiryTimestamp = type(uint256).max;
        address newDestination = solver;
        bytes memory call = hex"";
        uint48 discount = 0;
        uint32 timeToBuy = 1000;
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderId, address(compactSettler), newDestination, call, discount, timeToBuy);

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.prank(purchaser);
        token.approve(address(compactSettler), amount);
        vm.prank(purchaser);
        anotherToken.approve(address(compactSettler), amount);

        vm.prank(purchaser);

        // Modify the inputs.
        order.inputs[0][1] = order.inputs[0][1] - 1;
        bytes32 badOrderId = compactSettler.orderIdentifier(order);

        vm.expectRevert(abi.encodeWithSignature("OrderIdMismatch(bytes32,bytes32)", orderId, badOrderId));
        compactSettler.purchaseOrder(orderId, order, orderSolvedByIdentifier, purchaser, expiryTimestamp, newDestination, call, discount, timeToBuy, solverSignature);
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

    function test_validate_fills_one_solver(bytes32 solverIdentifier, bytes32 orderId, OrderFulfillmentDescription[] calldata orderFulfillmentDescription) external {
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
                keccak256(OutputEncodingLib.encodeFillDescriptionM(solverIdentifier, orderId, timestamps[i], outputDescriptions[i]))
            );
        }
        _validProofSeries[expectedProofPayload] = true;

        compactSettler.validateFills(localOracle, orderId, solverIdentifier, timestamps, outputDescriptions);
    }

    struct OrderFulfillmentDescriptionWithSolver {
        uint32 timestamp;
        bytes32 solver;
        OutputDescription outputDescription;
    }

    function test_validate_fills_multiple_solvers(bytes32 orderId, OrderFulfillmentDescriptionWithSolver[] calldata orderFulfillmentDescriptionWithSolver) external {
        vm.assume(orderFulfillmentDescriptionWithSolver.length > 0);
        address localOracle = address(this);

        bytes memory expectedProofPayload = hex"";
        uint32[] memory timestamps = new uint32[](orderFulfillmentDescriptionWithSolver.length);
        OutputDescription[] memory outputDescriptions = new OutputDescription[](orderFulfillmentDescriptionWithSolver.length);
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
                keccak256(OutputEncodingLib.encodeFillDescriptionM(solvers[i], orderId, timestamps[i], outputDescriptions[i]))
            );
        }
        _validProofSeries[expectedProofPayload] = true;

        compactSettler.validateFills(localOracle, orderId, solvers, timestamps, outputDescriptions);
    }

    // -- Larger Integration tests -- //

    function test_finalise_self(
        address non_solver
    ) external {
        vm.assume(non_solver != solver);

        vm.prank(swapper);
        uint256 amount = 1e18 / 10;
        uint256 tokenId = theCompact.deposit(address(token), alwaysOKAllocator, amount);

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
        CatalystCompactOrder memory order =
            CatalystCompactOrder({ user: address(swapper), nonce: 0, originChainId: block.chainid, fillDeadline: type(uint32).max, localOracle: alwaysYesOracle, inputs: inputs, outputs: outputs });

        // Make Compact
        bytes32 typeHash = TheCompactOrderType.BATCH_COMPACT_TYPE_HASH;
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(swapperPrivateKey, typeHash, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, this.orderHash(order));
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);

        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

        bytes32 orderId = compactSettler.orderIdentifier(order);

        bytes memory payload = OutputEncodingLib.encodeFillDescriptionM(solverIdentifier, orderId, uint32(block.timestamp), outputs[0]);
        bytes32 payloadHash = keccak256(payload);

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Other callers are disallowed:

        vm.prank(non_solver);

        vm.expectRevert(abi.encodeWithSignature("NotOrderOwner()"));
        compactSettler.finaliseSelf(order, signature, timestamps, solverIdentifier);

        assertEq(token.balanceOf(solver), 0);

        vm.expectCall(
            address(alwaysYesOracle),
            abi.encodeWithSignature("efficientRequireProven(bytes)", abi.encodePacked(order.outputs[0].chainId, order.outputs[0].remoteOracle, order.outputs[0].remoteFiller, payloadHash))
        );

        vm.prank(solver);
        compactSettler.finaliseSelf(order, signature, timestamps, solverIdentifier);
        vm.snapshotGasLastCall("finaliseSelf");

        assertEq(token.balanceOf(solver), amount);
    }

    function test_finalise_to(address non_solver, address destination) external {
        vm.assume(destination != address(compactSettler));
        vm.assume(destination != address(theCompact));
        vm.assume(non_solver != solver);

        vm.prank(swapper);
        uint256 amount = 1e18 / 10;
        uint256 tokenId = theCompact.deposit(address(token), alwaysOKAllocator, amount);

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
        CatalystCompactOrder memory order =
            CatalystCompactOrder({ user: address(swapper), nonce: 0, originChainId: block.chainid, fillDeadline: type(uint32).max, localOracle: alwaysYesOracle, inputs: inputs, outputs: outputs });

        // Make Compact
        bytes32 typeHash = TheCompactOrderType.BATCH_COMPACT_TYPE_HASH;
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(swapperPrivateKey, typeHash, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, this.orderHash(order));
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);

        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Other callers are disallowed:

        vm.prank(non_solver);

        vm.expectRevert(abi.encodeWithSignature("NotOrderOwner()"));
        compactSettler.finaliseTo(order, signature, timestamps, solverIdentifier, destination, hex"");

        assertEq(token.balanceOf(destination), 0);

        vm.prank(solver);
        compactSettler.finaliseTo(order, signature, timestamps, solverIdentifier, destination, hex"");
        vm.snapshotGasLastCall("finaliseTo");

        assertEq(token.balanceOf(destination), amount);
    }

    function test_finalise_for(address non_solver, address destination) external {
        vm.assume(destination != address(compactSettler));
        vm.assume(destination != address(theCompact));
        vm.assume(destination != address(swapper));
        vm.assume(destination != address(solver));
        vm.assume(non_solver != solver);

        vm.prank(swapper);
        uint256 amount = 1e18 / 10;
        uint256 tokenId = theCompact.deposit(address(token), alwaysOKAllocator, amount);

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
        CatalystCompactOrder memory order =
            CatalystCompactOrder({ user: address(swapper), nonce: 0, originChainId: block.chainid, fillDeadline: type(uint32).max, localOracle: alwaysYesOracle, inputs: inputs, outputs: outputs });

        // Make Compact
        bytes32 typeHash = TheCompactOrderType.BATCH_COMPACT_TYPE_HASH;
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(swapperPrivateKey, typeHash, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, this.orderHash(order));
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);

        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

        bytes32 orderId = compactSettler.orderIdentifier(order);

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Other callers are disallowed:

        bytes memory orderOwnerSignature = hex"";

        vm.prank(non_solver);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        compactSettler.finaliseFor(order, signature, timestamps, solverIdentifier, destination, hex"", orderOwnerSignature);

        assertEq(token.balanceOf(destination), 0);

        orderOwnerSignature = this.getOrderOpenSignature(solverPrivateKey, orderId, address(compactSettler), destination, hex"");

        vm.prank(non_solver);
        compactSettler.finaliseFor(order, signature, timestamps, solverIdentifier, destination, hex"", orderOwnerSignature);
        vm.snapshotGasLastCall("finaliseTo");

        assertEq(token.balanceOf(destination), amount);
    }

    function test_purchase_and_resolve() external { }
}
