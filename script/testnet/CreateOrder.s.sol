// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ResetPeriod } from "lib/the-compact/src/types/ResetPeriod.sol";
import { Scope } from "lib/the-compact/src/types/Scope.sol";

import { IdLib } from "lib/the-compact/src/lib/IdLib.sol";
import { EfficiencyLib } from "lib/the-compact/src/lib/EfficiencyLib.sol";

import { TheCompact } from "lib/the-compact/src/TheCompact.sol";

import { OutputDescriptionType } from "src/settlers/types/OutputDescriptionType.sol";
import { OutputDescription, OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

import { CatalystCompactOrder, TheCompactOrderType } from "src/settlers/compact/TheCompactOrderType.sol";

import { CoinFiller } from "src/fillers/coin/CoinFiller.sol";
import { WormholeOracle } from "src/oracles/wormhole/WormholeOracle.sol";

import { CompactSettler } from "src/settlers/compact/CompactSettler.sol";

import { ERC20 } from "lib/solady/src/tokens/ERC20.sol";

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";

contract CreateOrder is Script {
    using EfficiencyLib for address;
    using EfficiencyLib for uint96;
    using EfficiencyLib for ResetPeriod;
    using EfficiencyLib for Scope;
    using IdLib for address;

    TheCompact constant THE_COMPACT = TheCompact(0x56C438d1F007d41F345Cd0cE8B7EA92383C15884);
    address constant ALLOCATOR = 0x53F4cf4E63DbFcEc0b39677F62ACB2760A402635;
    address constant COIN_FILLER = 0x5D14806127d7CaAFcB8028C7736AE6B8AEC583d9;
    address constant COMPACT_SETTLER = 0x115513dd91E9D8A18A9B1469307D219830dc37fd;

    mapping(uint256 chainId => address) WORMHOLE_ORACLE;
    address constant ALWAYS_YES_ORACLE = 0xada1de62bE4F386346453A5b6F005BCdBE4515A1;

    constructor() {
        WORMHOLE_ORACLE[11155111] = 0x7Bc921c858C5390d9FD74c337dd009eC9A1B6B8f;
        WORMHOLE_ORACLE[84532] = 0xF08166e305d39f8066c19788f72Fd7322e4e01Fc;
    }

    function orderIdentifier(
        CatalystCompactOrder memory order
    ) internal view returns (bytes32) {
        bytes memory encodedOrder = abi.encodePacked(block.chainid, COMPACT_SETTLER, order.user, order.nonce, order.fillDeadline, order.localOracle, order.inputs, abi.encode(order.outputs));
        return keccak256(encodedOrder);
    }

    function getCompactBatchWitnessSignature(
        bytes32 typeHash,
        address arbiter,
        CatalystCompactOrder memory order
    ) internal view returns (bytes memory sig) {
        bytes32 domainSeparator = THE_COMPACT.DOMAIN_SEPARATOR();
        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(typeHash, arbiter, order.user, order.nonce, order.fillDeadline, keccak256(abi.encodePacked(order.inputs)), orderWitnessHash(order)))));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function orderWitnessHash(
        CatalystCompactOrder memory order
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(TheCompactOrderType.CATALYST_WITNESS_TYPE_HASH, order.fillDeadline, order.localOracle, OutputDescriptionType.hashOutputs(order.outputs)));
    }

    function registerAllocator() external {
        vm.broadcast();
        THE_COMPACT.__registerAllocator(ALLOCATOR, "");
    }

    function getTokenId(address token, Scope scope, ResetPeriod resetPeriod, address allocator) external pure returns(uint256 id) {

        // Derive resource lock ID (pack scope, reset period, allocator ID, & token).
        return id = id = ((scope.asUint256() << 255) | (resetPeriod.asUint256() << 252) | (allocator.usingAllocatorId().asUint256() << 160) | token.asUint256());
    }

    function deposit(address token, uint256 amount) external returns(uint256 id) {
        vm.startBroadcast();

        if (ERC20(token).allowance(msg.sender, address(THE_COMPACT)) < amount) ERC20(token).approve(address(THE_COMPACT), amount);

        return id = THE_COMPACT.deposit(token, ALLOCATOR, ResetPeriod.OneDay, Scope.Multichain, amount, msg.sender);
    }

    // 36286452483532273188258183071097127586156282419649613466036116694645176389502
    // 0x8bff75c2f27cb873be99dc6e447c2e08b86a330c4a568ccfd618c29966b5c4d2
    // 0xed79a496ac82c23f97aa5cac1a9689ec715c0cb003b3899f355c1a4dbbfb3e1b49262a1cab5f455e4275ba0d07d51cb2aeabd235b17a0211cf37ede4c65caf311b

    function signIntent(uint256 tokenId, uint256 inputAmount, address outToken, uint256 outputAmount, uint256 nonce, uint256 remoteChain) external returns(bytes32 orderId, bytes memory sponsorSig, CatalystCompactOrder memory order) {
        // Manage Inputs
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, inputAmount];

        // Manage Outputs

        vm.startBroadcast();

        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(COIN_FILLER)))),
            remoteOracle: bytes32(uint256(uint160(WORMHOLE_ORACLE[remoteChain]))),
            chainId: remoteChain,
            token: bytes32(uint256(uint160(address(outToken)))),
            amount: outputAmount,
            recipient: bytes32(uint256(uint160(msg.sender))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        // Construct our order.

        order =
            CatalystCompactOrder({ user: address(msg.sender), nonce: nonce, originChainId: block.chainid, fillDeadline: uint32(block.timestamp + 1 days), localOracle: ALWAYS_YES_ORACLE, inputs: inputs, outputs: outputs });

        // Create Associated Signature
        bytes32 typeHash = TheCompactOrderType.BATCH_COMPACT_TYPE_HASH;
        sponsorSig = getCompactBatchWitnessSignature(
            typeHash,
            COMPACT_SETTLER,
            order
        );

        orderId = orderIdentifier(order);
        console.logBytes32(orderId);
        console.logBytes(sponsorSig);
    }

    function signIntentNonEVM(
        bytes32 remoteFiller,
        bytes32 remoteOracle,
        uint256 tokenId,
        uint256 inputAmount,
        bytes32 outToken,
        uint256 outputAmount,
        uint256 nonce,
        uint256 remoteChain,
        bytes32 recipient,
        uint32 fillDeadline
    ) external {
        // Manage Inputs
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, inputAmount];

        // Manage Outputs

        vm.startBroadcast();

        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: remoteFiller,
            remoteOracle: remoteOracle,
            chainId: remoteChain,
            token: outToken,
            amount: outputAmount,
            recipient: recipient,
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        // Construct our order.

        CatalystCompactOrder memory order =
            CatalystCompactOrder({ user: address(msg.sender), nonce: nonce, originChainId: block.chainid, fillDeadline: fillDeadline, localOracle: ALWAYS_YES_ORACLE, inputs: inputs, outputs: outputs });

        // Create Associated Signature
        bytes32 typeHash = TheCompactOrderType.BATCH_COMPACT_TYPE_HASH;
        bytes memory sponsorSig = getCompactBatchWitnessSignature(
            typeHash,
            COMPACT_SETTLER,
            order
        );

        bytes32 orderId = orderIdentifier(order);
        console.logBytes32(orderId);
        console.logBytes(sponsorSig);
    }

    function receiveMessage(
        bytes calldata rawMessage
    ) external {
        WormholeOracle(WORMHOLE_ORACLE[block.chainid]).receiveMessage(rawMessage);
    }

    function fillOutput(bytes32 orderId, address token, uint256 amount, bytes32 recipient) external {
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(COIN_FILLER)))),
            remoteOracle: bytes32(uint256(uint160(WORMHOLE_ORACLE[block.chainid]))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(token)))),
            amount: amount,
            recipient: recipient,
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        vm.startBroadcast();

        if (ERC20(token).allowance(msg.sender, COIN_FILLER) < amount) ERC20(token).approve(COIN_FILLER, amount);

        bytes32 solverIdentifier = bytes32(uint256(uint160(msg.sender)));
        CoinFiller(COIN_FILLER).fill(orderId, outputs[0], solverIdentifier);
    }

    function fillOutputNonEVM(bytes32 orderId, address token, uint256 amount, bytes32 recipient, bytes32 proposedSolver) external {
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(COIN_FILLER)))),
            remoteOracle: bytes32(uint256(uint160(WORMHOLE_ORACLE[block.chainid]))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(token)))),
            amount: amount,
            recipient: recipient,
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        vm.startBroadcast();

        if (ERC20(token).allowance(msg.sender, COIN_FILLER) < amount) ERC20(token).approve(COIN_FILLER, amount);

        CoinFiller(COIN_FILLER).fill(orderId, outputs[0], proposedSolver);
    }

    function submitOutput(bytes32 orderId, address token, uint256 amount, bytes32 recipient, uint32 timestamp) external {
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(COIN_FILLER)))),
            remoteOracle: bytes32(uint256(uint160(WORMHOLE_ORACLE[block.chainid]))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(token)))),
            amount: amount,
            recipient: recipient,
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        vm.startBroadcast();
        bytes32 solverIdentifier = bytes32(uint256(uint160(msg.sender)));
        
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = OutputEncodingLib.encodeFillDescriptionM(solverIdentifier, orderId, timestamp, outputs[0]);
        WormholeOracle(WORMHOLE_ORACLE[block.chainid]).submit(COIN_FILLER, payloads);
    }

    function submitOutputNonEVM(bytes32 orderId, address token, uint256 amount, bytes32 recipient, uint32 timestamp, bytes32 proposedSolver) external {
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(COIN_FILLER)))),
            remoteOracle: bytes32(uint256(uint160(WORMHOLE_ORACLE[block.chainid]))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(token)))),
            amount: amount,
            recipient: recipient,
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        vm.startBroadcast();
        
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = OutputEncodingLib.encodeFillDescriptionM(proposedSolver, orderId, timestamp, outputs[0]);
        WormholeOracle(WORMHOLE_ORACLE[block.chainid]).submit(COIN_FILLER, payloads);
    }

    function finaliseIntent(
        uint256 tokenId,
        uint256 inputAmount,
        address outToken,
        uint256 outputAmount,
        uint256 nonce,
        uint256 remoteChain,
        bytes calldata signature,
        uint32 timestamp,
        uint32 fillDeadline) external {
        // Manage Inputs
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, inputAmount];

        // Manage Outputs


        vm.startBroadcast();

        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(COIN_FILLER)))),
            remoteOracle: bytes32(uint256(uint160(WORMHOLE_ORACLE[remoteChain]))),
            chainId: remoteChain,
            token: bytes32(uint256(uint160(address(outToken)))),
            amount: outputAmount,
            recipient: bytes32(uint256(uint160(msg.sender))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        // Construct our order.

        CatalystCompactOrder memory order =
            CatalystCompactOrder({ user: address(msg.sender), nonce: nonce, originChainId: block.chainid, fillDeadline: fillDeadline, localOracle: ALWAYS_YES_ORACLE, inputs: inputs, outputs: outputs });


        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = timestamp;
        bytes32 solverIdentifier = bytes32(uint256(uint160(msg.sender)));

        CompactSettler(COMPACT_SETTLER).finaliseSelf(order, abi.encode(signature, hex""), timestamps, solverIdentifier);
    }

    function finaliseIntentNonEVM(
        bytes32 remoteFiller,
        bytes32 remoteOracle,
        uint256 tokenId,
        uint256 inputAmount,
        bytes32 outToken,
        uint256 outputAmount,
        uint256 nonce,
        uint256 remoteChain,
        bytes32 recipient,
        bytes32 proposedSolver,
        address user,
        uint32 fillDeadline,
        uint32 timestamp,
        bytes calldata signature
    ) external {

          // Manage Inputs
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, inputAmount];

        // Manage Outputs


        vm.startBroadcast();

        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: remoteFiller,
            remoteOracle: remoteOracle,
            chainId: remoteChain,
            token: outToken,
            amount: outputAmount,
            recipient: recipient,
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        // Construct our order.

        CatalystCompactOrder memory order =
            CatalystCompactOrder({ user: user, nonce: nonce, originChainId: block.chainid, fillDeadline: fillDeadline, localOracle: ALWAYS_YES_ORACLE, inputs: inputs, outputs: outputs });


        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = timestamp;
        bytes32 solverIdentifier = proposedSolver;

        CompactSettler(COMPACT_SETTLER).finaliseSelf(order, abi.encode(signature, hex""), timestamps, solverIdentifier);
    }
}
