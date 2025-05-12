// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { CoinFiller } from "src/fillers/coin/CoinFiller.sol";
import { CompactSettlerWithDeposit } from "src/settlers/compact/CompactSettlerWithDeposit.sol";

import { AllowOpenType } from "src/settlers/types/AllowOpenType.sol";
import { OrderPurchase, OrderPurchaseType } from "src/settlers/types/OrderPurchaseType.sol";

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
        address compact,
        address initialOwner
    ) CompactSettlerWithDeposit(compact, initialOwner) { }

    function validateFills(CatalystCompactOrder calldata order, bytes32 orderId, bytes32[] calldata solvers, uint32[] calldata timestamps) external view {
        _validateFills(order, orderId, solvers, timestamps);
    }

    function validateFills(CatalystCompactOrder calldata order, bytes32 orderId, bytes32 solver, uint32[] calldata timestamps) external view {
        _validateFills(order, orderId, solver, timestamps);
    }
}

contract TestCompactSettler is Test {
    event Transfer(address from, address to, uint256 amount);
    event Transfer(address by, address from, address to, uint256 id, uint256 amount);
    event CompactRegistered(address indexed sponsor, bytes32 claimHash, bytes32 typehash);
    event NextGovernanceFee(uint64 nextGovernanceFee, uint64 nextGovernanceFeeTime);
    event GovernanceFeeChanged(uint64 oldGovernanceFee, uint64 newGovernanceFee);

    uint64 constant GOVERNANCE_FEE_CHANGE_DELAY = 7 days;
    uint256 constant MAX_GOVERNANCE_FEE = 10 ** 18 * 0.1; // 10%

    MockDepositCompactSettler compactSettler;
    CoinFiller coinFiller;

    // Oracles
    address alwaysYesOracle;
    
    address owner;

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
    bytes12 alwaysOkAllocatorLockTag;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public virtual {
        theCompact = new TheCompact();

        alwaysOKAllocator = address(new AlwaysOKAllocator());

        uint96 alwaysOkAllocatorId = theCompact.__registerAllocator(alwaysOKAllocator, "");

        // use scope 0 and reset period 0. This is okay as long as we don't use anything time based.
        alwaysOkAllocatorLockTag = bytes12(alwaysOkAllocatorId);

        DOMAIN_SEPARATOR = EIP712(address(theCompact)).DOMAIN_SEPARATOR();

        owner = makeAddr("owner");

        compactSettler = new MockDepositCompactSettler(address(theCompact), owner);
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

    function witnessHash(
        CatalystCompactOrder memory order
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    bytes(
                        "Mandate(uint32 fillDeadline,address localOracle,MandateOutput[] outputs)MandateOutput(bytes32 remoteOracle,bytes32 remoteFiller,uint256 chainId,bytes32 token,uint256 amount,bytes32 recipient,bytes remoteCall,bytes fulfillmentContext)"
                    )
                ),
                order.fillDeadline,
                order.localOracle,
                outputsHash(order.outputs)
            )
        );
    }

    function outputsHash(
        OutputDescription[] memory outputs
    ) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](outputs.length);
        for (uint256 i = 0; i < outputs.length; ++i) {
            OutputDescription memory output = outputs[i];
            hashes[i] = keccak256(
                abi.encode(
                    keccak256(bytes("MandateOutput(bytes32 remoteOracle,bytes32 remoteFiller,uint256 chainId,bytes32 token,uint256 amount,bytes32 recipient,bytes remoteCall,bytes fulfillmentContext)")),
                    output.remoteOracle,
                    output.remoteFiller,
                    output.chainId,
                    output.token,
                    output.amount,
                    output.recipient,
                    keccak256(output.remoteCall),
                    keccak256(output.fulfillmentContext)
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function compactHash(address arbiter, address sponsor, uint256 nonce, uint256 expires, CatalystCompactOrder calldata order) external pure returns (bytes32) {
        return TheCompactOrderType.compactHash(arbiter, sponsor, nonce, expires, order);
    }

    function getOrderPurchaseSignature(
        uint256 privateKey,
        OrderPurchase calldata orderPurchase
    ) external view returns (bytes memory sig) {
        bytes32 domainSeparator = compactSettler.DOMAIN_SEPARATOR();
        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, OrderPurchaseType.hashOrderPurchase(orderPurchase)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function getOrderOpenSignature(uint256 privateKey, bytes32 orderId, bytes32 destination, bytes calldata call) external view returns (bytes memory sig) {
        bytes32 domainSeparator = compactSettler.DOMAIN_SEPARATOR();
        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, AllowOpenType.hashAllowOpen(orderId, destination, call)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function getCompactBatchWitnessSignature(
        uint256 privateKey,
        address arbiter,
        address sponsor,
        uint256 nonce,
        uint256 expires,
        uint256[2][] memory idsAndAmounts,
        bytes32 witness
    ) internal view returns (bytes memory sig) {
        bytes32 domainSeparator = EIP712(address(theCompact)).DOMAIN_SEPARATOR();
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        keccak256(
                            bytes(
                                "BatchCompact(address arbiter,address sponsor,uint256 nonce,uint256 expires,uint256[2][] idsAndAmounts,Mandate mandate)Mandate(uint32 fillDeadline,address localOracle,MandateOutput[] outputs)MandateOutput(bytes32 remoteOracle,bytes32 remoteFiller,uint256 chainId,bytes32 token,uint256 amount,bytes32 recipient,bytes remoteCall,bytes fulfillmentContext)"
                            )
                        ),
                        arbiter,
                        sponsor,
                        nonce,
                        expires,
                        keccak256(abi.encodePacked(idsAndAmounts)),
                        witness
                    )
                )
            )
        );

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
        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: address(target),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: localOracle,
            inputs: inputs,
            outputs: outputs
        });

        vm.prank(swapper);
        token.approve(address(compactSettler), amount);

        bytes32 claimHash = this.compactHash(address(compactSettler), order.user, order.nonce, order.fillDeadline, order);
        bytes32 typehash = 0x3df4b6efdfbd05bc0129a40c10b9e80a519127db6100fb77877a4ac4ac191af7;

        vm.expectEmit();
        emit CompactRegistered(target, claimHash, typehash);

        vm.prank(swapper);
        compactSettler.depositFor(order);
    }

    function hashOrderPurchase(OrderPurchase calldata orderPurchase) external pure returns (bytes32) {
        return OrderPurchaseType.hashOrderPurchase(orderPurchase);
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
        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: address(target),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));

        bytes32 orderId = compactSettler.orderIdentifier(order);

        OrderPurchase memory orderPurchase = OrderPurchase({
            orderId: orderId,
            destination: solver,
            call: hex"",
            discount: 0,
            timeToBuy: 1000
        });
        uint256 expiryTimestamp = type(uint256).max;
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderPurchase);

        uint32 currentTime = 10000;
        vm.warp(currentTime);

        vm.prank(purchaser);
        token.approve(address(compactSettler), amount);
        vm.prank(purchaser);
        anotherToken.approve(address(compactSettler), amount);

        vm.prank(purchaser);
        compactSettler.purchaseOrder(orderPurchase, order, orderSolvedByIdentifier, bytes32(uint256(uint160(purchaser))), expiryTimestamp, solverSignature);

        (uint32 storageLastOrderTimestamp, bytes32 storagePurchaser) = compactSettler.purchasedOrders(orderSolvedByIdentifier, orderId);
        assertEq(storageLastOrderTimestamp, currentTime - orderPurchase. timeToBuy);
        assertEq(storagePurchaser, bytes32(uint256(uint160(purchaser))));
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
        CatalystCompactOrder memory order = CatalystCompactOrder({
            user: address(target),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        bytes32 orderSolvedByIdentifier = bytes32(uint256(uint160(solver)));

        bytes32 orderId = compactSettler.orderIdentifier(order);


        OrderPurchase memory orderPurchase = OrderPurchase({
            orderId: orderId,
            destination: solver,
            call: hex"",
            discount: 0,
            timeToBuy: 1000
        });
        bytes memory solverSignature = this.getOrderPurchaseSignature(solverPrivateKey, orderPurchase);

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


        uint256 expiryTimestamp = type(uint256).max;
        vm.expectRevert(abi.encodeWithSignature("OrderIdMismatch(bytes32,bytes32)", orderId, badOrderId));
        compactSettler.purchaseOrder(orderPurchase, order, orderSolvedByIdentifier, bytes32(uint256(uint160(purchaser))), expiryTimestamp, solverSignature);
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

        compactSettler.validateFills(CatalystCompactOrder({
            user: address(0),
            nonce: 0,
            originChainId: 0,
            expires: type(uint32).max,
            fillDeadline: type(uint32).max,
            localOracle: localOracle,
            inputs: new uint256[2][](0),
            outputs: outputDescriptions
        }), orderId, solverIdentifier, timestamps);
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

        compactSettler.validateFills(CatalystCompactOrder({
            user: address(0),
            nonce: 0,
            originChainId: 0,
            expires: type(uint32).max,
            fillDeadline: type(uint32).max,
            localOracle: localOracle,
            inputs: new uint256[2][](0),
            outputs: outputDescriptions
        }), orderId, solvers, timestamps);
    }

    // -- Larger Integration tests -- //

    function test_finalise_self(
        address non_solver
    ) external {
        vm.assume(non_solver != solver);

        vm.prank(swapper);
        uint256 amount = 1e18 / 10;
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
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order));
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

    function test_revert_finalise_self_too_late(address non_solver, uint32 fillDeadline, uint32 filledAt) external {
        vm.assume(non_solver != solver);
        vm.assume(fillDeadline < filledAt);

        vm.prank(swapper);
        uint256 amount = 1e18 / 10;
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

        bytes memory sponsorSig = getCompactBatchWitnessSignature(swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order));
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
        vm.assume(token.balanceOf(destination) == 0);
        vm.assume(non_solver != solver);

        vm.prank(swapper);
        uint256 amount = 1e18 / 10;
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
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order));
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);

        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Other callers are disallowed:

        vm.prank(non_solver);

        vm.expectRevert(abi.encodeWithSignature("NotOrderOwner()"));
        compactSettler.finaliseTo(order, signature, timestamps, solverIdentifier, bytes32(uint256(uint160(destination))), hex"");

        assertEq(token.balanceOf(destination), 0);

        vm.prank(solver);
        compactSettler.finaliseTo(order, signature, timestamps, solverIdentifier, bytes32(uint256(uint160(destination))), hex"");
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
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order));
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
        compactSettler.finaliseFor(order, signature, timestamps, solverIdentifier, bytes32(uint256(uint160(destination))), hex"", orderOwnerSignature);

        assertEq(token.balanceOf(destination), 0);

        orderOwnerSignature = this.getOrderOpenSignature(solverPrivateKey, orderId, bytes32(uint256(uint160(destination))), hex"");

        vm.prank(non_solver);
        compactSettler.finaliseFor(order, signature, timestamps, solverIdentifier, bytes32(uint256(uint160(destination))), hex"", orderOwnerSignature);
        vm.snapshotGasLastCall("finaliseFor");

        assertEq(token.balanceOf(destination), amount);
    }

    // --- Fee tests --- //

    function test_invalid_governance_fee(
        uint64 fee
    ) public {
        vm.assume(fee > MAX_GOVERNANCE_FEE);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        compactSettler.setGovernanceFee(fee);
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

        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);

        assertEq(compactSettler.governanceFee(), 0);

        vm.expectEmit();
        emit GovernanceFeeChanged(0, fee);
        compactSettler.applyGovernanceFee();

        assertEq(compactSettler.governanceFee(), fee);
    }

    function test_finalise_self_with_fee(uint64 fee) external {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.prank(owner);
        compactSettler.setGovernanceFee(fee);
        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);
        compactSettler.applyGovernanceFee();

        vm.prank(swapper);
        uint256 amount = 1e18 / 10;
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
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(swapperPrivateKey, address(compactSettler), swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order));
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);

        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));

        bytes32 orderId = compactSettler.orderIdentifier(order);

        bytes memory payload = OutputEncodingLib.encodeFillDescriptionM(solverIdentifier, orderId, uint32(block.timestamp), outputs[0]);

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        uint256 govFeeAmount = amount * fee / 10**18;
        uint256 amountPostFee = amount - govFeeAmount;

        vm.prank(solver);
        compactSettler.finaliseSelf(order, signature, timestamps, solverIdentifier);
        vm.snapshotGasLastCall("finaliseSelf");

        assertEq(token.balanceOf(solver), amountPostFee);
        assertEq(theCompact.balanceOf(owner, tokenId), govFeeAmount);
    }
}
