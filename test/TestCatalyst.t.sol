// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;


import "forge-std/Test.sol";

import { CatalystCompactSettler } from "../src/reactors/settler/compact/CatalystCompactSettler.sol";
import { CoinFiller } from "../src/reactors/filler/CoinFiller.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { AlwaysYesOracle } from "./mocks/AlwaysYesOracle.sol";

import { OutputDescription, CatalystOrderType } from "../src/reactors/CatalystOrderType.sol";
import { TheCompactOrderType, CatalystCompactFilledOrder } from "../src/reactors/settler/compact/TheCompactOrderType.sol";
import { GaslessCrossChainOrder } from "../src/interfaces/IERC7683.sol";

import { IdentifierLib } from "../src/libs/IdentifierLib.sol";
import { OutputEncodingLib } from "../src/libs/OutputEncodingLib.sol";
import { MessageEncodingLib } from "../src/oracles/MessageEncodingLib.sol";

import { Messages } from "../src/oracles/wormhole/external/wormhole/Messages.sol";
import { Setters } from "../src/oracles/wormhole/external/wormhole/Setters.sol";
import { WormholeOracle } from "../src/oracles/wormhole/WormholeOracle.sol";
import { Structs } from "../src/oracles/wormhole/external/wormhole/Structs.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";
import { AlwaysOKAllocator } from "the-compact/src/test/AlwaysOKAllocator.sol";

interface EIP712 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initializationCode) external payable returns (address deploymentAddress);
}

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

contract TestCatalyst is Test {
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

    TheCompact public theCompact;
    address alwaysOKAllocator;
    bytes32 DOMAIN_SEPARATOR;

    function test() external pure { }

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

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        typeHash,
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

    function orderHash(
        CatalystCompactFilledOrder calldata order
    ) external pure returns (bytes32) {
        return TheCompactOrderType.orderHash(order);
    }

    function encodeMessage(bytes32 remoteIdentifier, bytes[] calldata payloads) external pure returns (bytes memory) {
        return MessageEncodingLib.encodeMessage(remoteIdentifier, payloads);
    }

    function setUp() public virtual {
        theCompact = new TheCompact();

        alwaysOKAllocator = address(new AlwaysOKAllocator());

        theCompact.__registerAllocator(alwaysOKAllocator, "");

        DOMAIN_SEPARATOR = EIP712(address(theCompact)).DOMAIN_SEPARATOR();

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
        address wormholeDeployment = makeAddr("wormholeOracle");
        deployCodeTo("WormholeOracle.sol", abi.encode(address(this), address(messages)), wormholeDeployment);
        wormholeOracle = WormholeOracle(wormholeDeployment);

        wormholeOracle.setChainMap(uint16(block.chainid), block.chainid);

        (testGuardian, testGuardianPrivateKey) = makeAddrAndKey("testGuardian");
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

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, amount];
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
        CatalystCompactFilledOrder memory order = CatalystCompactFilledOrder({
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: type(uint32).max,
            localOracle: alwaysYesOracle,
            collateralToken: address(0),
            collateralAmount: uint256(0),
            proofDeadline: type(uint32).max,
            challengeDeadline: type(uint32).max,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        bytes32 typeHash = TheCompactOrderType.BATCH_COMPACT_TYPE_HASH;
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
            this.orderHash(order)
        );
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);
        
        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));
        uint32[] memory timestamps = new uint32[](1);

        vm.prank(solver);
        catalystCompactSettler.finaliseSelf(order, signature, timestamps, solver);
    }

    function _buildPreMessage(uint16 emitterChainId, bytes32 emitterAddress) internal pure returns(bytes memory preMessage) {
        return abi.encodePacked(
            hex"000003e8" hex"00000001",
            emitterChainId,
            emitterAddress,
            hex"0000000000000539" hex"0f"
        );
    } 

    function makeValidVAA(uint16 emitterChainId, bytes32 emitterAddress, bytes memory message) internal view returns(bytes memory validVM) {
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
        bytes32 remoteOracle = IdentifierLib.getIdentifier(address(coinFiller), address(wormholeOracle));

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, amount];
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
        CatalystCompactFilledOrder memory order = CatalystCompactFilledOrder({
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: type(uint32).max,
            localOracle: address(wormholeOracle),
            collateralToken: address(0),
            collateralAmount: uint256(0),
            proofDeadline: type(uint32).max,
            challengeDeadline: type(uint32).max,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        bytes32 typeHash = TheCompactOrderType.BATCH_COMPACT_TYPE_HASH;
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
            this.orderHash(order)
        );
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);
        
        // Initiation is over. We need to fill the order.

        bytes32 solverIdentifier = bytes32(uint256(uint160((solver))));
        bytes32[] memory orderIds = new bytes32[](1);

        bytes32 orderId = catalystCompactSettler.orderIdentifier(order);
        orderIds[0] = orderId;

        vm.prank(solver);
        coinFiller.fillThrow(orderIds, outputs, solverIdentifier);
        vm.snapshotGasLastCall("fillThrow");

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = OutputEncodingLib.encodeFillDescriptionM(solverIdentifier, orderId, uint32(block.timestamp), outputs[0]);

        bytes memory expectedMessageEmitted = this.encodeMessage(remoteOracle, payloads);

        vm.expectEmit();
        emit PackagePublished(0, expectedMessageEmitted, 15);
        wormholeOracle.submit(address(coinFiller), payloads);
        vm.snapshotGasLastCall("submit");

        bytes memory vaa = makeValidVAA(uint16(block.chainid), bytes32(uint256(uint160(address(wormholeOracle)))), expectedMessageEmitted);

        wormholeOracle.receiveMessage(vaa);
        vm.snapshotGasLastCall("receiveMessage");

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);
        
        vm.prank(solver);
        catalystCompactSettler.finaliseSelf(order, signature, timestamps, solver);
        vm.snapshotGasLastCall("finaliseSelf");
    }
}