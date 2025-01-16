// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;


import "forge-std/Test.sol";

import { DeployCompact } from "./DeployCompact.t.sol";

import { CatalystCompactSettler } from "../src/reactors/settler/CatalystCompactSettler.sol";
import { CoinFiller } from "../src/reactors/filler/CoinFiller.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { AlwaysYesOracle } from "./mocks/AlwaysYesOracle.sol";

import { InputDescription, OutputDescription, CatalystOrderData, CatalystOrderType } from "../src/reactors/CatalystOrderType.sol";
import { GaslessCrossChainOrder } from "../src/interfaces/IERC7683.sol";

import { IdentifierLib } from "../src/libs/IdentifierLib.sol";
import { OutputEncodingLibrary } from "../src/reactors/OutputEncodingLibrary.sol";
import { PayloadEncodingLib } from "../src/oracles/PayloadEncodingLib.sol";

import { Messages } from "../src/oracles/wormhole/external/wormhole/Messages.sol";
import { Setters } from "../src/oracles/wormhole/external/wormhole/Setters.sol";
import { WormholeOracle } from "../src/oracles/wormhole/WormholeOracle.sol";
import { Structs } from "../src/oracles/wormhole/external/wormhole/Structs.sol";

event PackagePublished(uint32 nonce, bytes payload, uint8 consistencyLevel);
contract ExportedMessages is Messages, Setters {
    function storeGuardianSetPub(Structs.GuardianSet memory set, uint32 index) public {
        return super.storeGuardianSet(set, index);
    }

    function publishMessage(
        uint32 nonce,
        bytes calldata payload,
        uint8 consistencyLevel
    ) external payable returns (uint64) {
        emit PackagePublished(nonce, payload, consistencyLevel);
        return 0;
    }
}

contract TestCatalyst is DeployCompact {
    CatalystCompactSettler catalystCompactSettler;
    CoinFiller coinFiller;

    // Oracles
    address alwaysYesOracle;
    ExportedMessages messages;
    WormholeOracle wormholeOracle;

    uint256 swapperPrivateKey;
    address swapper;
    uint256 solverPrivateKey;
    address solver;
    uint256 testGuardianPrivateKey;
    address testGuardian;

    MockERC20 token;
    MockERC20 anotherToken;

    function orderHash(
        GaslessCrossChainOrder memory order,
        CatalystOrderData memory orderData
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CatalystOrderType.GASSLESS_CROSS_CHAIN_ORDER_TYPE_HASH,
                order.originSettler,
                order.user,
                order.nonce,
                order.originChainId,
                order.openDeadline,
                order.fillDeadline,
                order.orderDataType,
                CatalystOrderType.hashOrderDataM(orderData)
            )
        );
    }

    function encodeMessage(bytes32 remoteIdentifier, bytes[] calldata payloads) external pure returns (bytes memory) {
        return PayloadEncodingLib.encodeMessage(remoteIdentifier, payloads);
    }

    function setUp() public override virtual {
        super.setUp();

        catalystCompactSettler = new CatalystCompactSettler(address(theCompact));
        coinFiller = new CoinFiller();
        alwaysYesOracle = address(new AlwaysYesOracle());

        token = new MockERC20("Mock ERC20", "MOCK", 18);
        anotherToken = new MockERC20("Mock2 ERC20", "MOCK2", 18);

        (swapper, swapperPrivateKey) = makeAddrAndKey("swapper");
        (solver, solverPrivateKey) = makeAddrAndKey("swapper");

        token.mint(swapper, 1e18);

        anotherToken.mint(solver, 1e18);
        
        vm.prank(swapper);
        token.approve(address(theCompact), type(uint256).max);
        vm.prank(solver);
        anotherToken.approve(address(coinFiller), type(uint256).max);

        // Oracles

        messages = new ExportedMessages();
        address wormholeDeployment = address(uint160(uint128(uint160(makeAddr("wormholeOracle")))));
        deployCodeTo("WormholeOracle.sol", abi.encode(address(this), address(messages)), wormholeDeployment);
        wormholeOracle = WormholeOracle(wormholeDeployment);

        wormholeOracle.setChainMap(uint16(block.chainid), block.chainid);

        (testGuardian, testGuardianPrivateKey) = makeAddrAndKey("signer");
        // initialize guardian set with one guardian
        address[] memory keys = new address[](1);
        keys[0] = testGuardian;
        Structs.GuardianSet memory guardianSet = Structs.GuardianSet(keys, 0);
        require(messages.quorum(guardianSet.keys.length) == 1, "Quorum should be 1");

        messages.storeGuardianSetPub(guardianSet, uint32(0));
    }

    function test_deposit_compact() external {
        vm.prank(swapper);
        theCompact.deposit(address(token), alwaysOKAllocator, 1e18/10);
    }

    function test_deposit_and_claim() external {
        vm.prank(swapper);
        uint256 amount = 1e18/10;
        uint256 tokenId = theCompact.deposit(address(token), alwaysOKAllocator, amount);

        InputDescription[] memory inputs = new InputDescription[](1);
        inputs[0] = InputDescription({
            tokenId: tokenId,
            amount: amount
        });
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(alwaysYesOracle))),
            chainId: block.chainid,
            token: bytes32(tokenId),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystOrderData memory orderData = CatalystOrderData({
            localOracle: alwaysYesOracle,
            collateralToken: address(0),
            collateralAmount: uint256(0),
            proofDeadline: type(uint32).max,
            challengeDeadline: type(uint32).max,
            inputs: inputs,
            outputs: outputs
        });
        GaslessCrossChainOrder memory order = GaslessCrossChainOrder({
            originSettler: address(catalystCompactSettler),
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            openDeadline: type(uint32).max,
            fillDeadline: type(uint32).max,
            orderDataType: CatalystOrderType.CATALYST_ORDER_DATA_TYPE_HASH,
            orderData: abi.encode(orderData)
        });

        // Make Compact
        bytes32 typeHash = CatalystOrderType.BATCH_COMPACT_TYPE_HASH;
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(
            swapperPrivateKey,
            typeHash,
            address(catalystCompactSettler),
            swapper,
            0,
            type(uint32).max,
            idsAndAmounts,
            orderHash(order, orderData)
        );
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);
        
        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));
        uint40[] memory timestamps = new uint40[](1);
        bytes memory originFllerData = abi.encode(solverIdentifier, timestamps);

        vm.prank(solver);
        catalystCompactSettler.openFor(order, signature, originFllerData);
    }

    function _buildPreMessage(uint16 emitterChainId, bytes32 emitterAddress) internal pure returns(bytes memory preMessage) {
        return abi.encodePacked(
            hex"000003e8" hex"00000001",
            emitterChainId,
            emitterAddress,
            hex"0000000000000539" hex"0f"
        );
    } 

    function makeValidVM(uint16 emitterChainId, bytes32 emitterAddress, bytes memory message) internal view returns(bytes memory validVM) {
        bytes memory postvalidVM = abi.encodePacked(_buildPreMessage(emitterChainId, emitterAddress), message);
        bytes32 vmHash = keccak256(abi.encodePacked(keccak256(postvalidVM)));
        (uint8 v, bytes32 r,  bytes32 s) = vm.sign(testGuardianPrivateKey, vmHash);

        validVM = abi.encodePacked(
            hex"01" hex"00000000" hex"01",
            uint8(0),
            r, s, v - 27,
            postvalidVM
        );
    }

    function test_entire_flow() external {
        vm.prank(swapper);
        uint256 amount = 1e18/10;
        uint256 tokenId = theCompact.deposit(address(token), alwaysOKAllocator, amount);

        address localOracle = address(wormholeOracle);
        bytes32 remoteOracle = IdentifierLib.getIdentifier(address(coinFiller), address(uint160(uint128(uint160(address(wormholeOracle))))));

        InputDescription[] memory inputs = new InputDescription[](1);
        inputs[0] = InputDescription({
            tokenId: tokenId,
            amount: amount
        });
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteOracle: remoteOracle,
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystOrderData memory orderData = CatalystOrderData({
            localOracle: localOracle,
            collateralToken: address(0),
            collateralAmount: uint256(0),
            proofDeadline: type(uint32).max,
            challengeDeadline: type(uint32).max,
            inputs: inputs,
            outputs: outputs
        });
        GaslessCrossChainOrder memory order = GaslessCrossChainOrder({
            originSettler: address(catalystCompactSettler),
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            openDeadline: type(uint32).max,
            fillDeadline: type(uint32).max,
            orderDataType: CatalystOrderType.CATALYST_ORDER_DATA_TYPE_HASH,
            orderData: abi.encode(orderData)
        });

        // Make Compact
        bytes32 typeHash = CatalystOrderType.BATCH_COMPACT_TYPE_HASH;
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(
            swapperPrivateKey,
            typeHash,
            address(catalystCompactSettler),
            swapper,
            0,
            type(uint32).max,
            idsAndAmounts,
            orderHash(order, orderData)
        );
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);
        
        // Initiation is over. We need to fill the order.

        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));
        bytes32[] memory orderIds = new bytes32[](1);

        bytes32 orderId = catalystCompactSettler.orderIdentifier(order);
        orderIds[0] = orderId;

        vm.startPrank(solver);
        coinFiller.fillThrow(orderIds, outputs, solverIdentifier);

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = OutputEncodingLibrary.encodeOutputDescriptionIntoPayload(solverIdentifier, uint40(block.timestamp), orderId, outputs[0]);

        bytes memory expectedMessageEmitted = this.encodeMessage(remoteOracle, payloads);

        vm.expectEmit();
        emit PackagePublished(0, expectedMessageEmitted, 15);
        wormholeOracle.submit(address(coinFiller), payloads);

        bytes memory vm = makeValidVM(uint16(block.chainid), bytes32(uint256(uint160(address(wormholeOracle)))), expectedMessageEmitted);

        wormholeOracle.receiveMessage(vm);

        uint40[] memory timestamps = new uint40[](1);
        timestamps[0] = uint40(block.timestamp);
        bytes memory originFllerData = abi.encode(solverIdentifier, timestamps);
        
        catalystCompactSettler.openFor(order, signature, originFllerData);
    }
}