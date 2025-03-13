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
        return keccak256(abi.encodePacked(block.chainid, address(this), order.user, order.nonce, order.fillDeadline, order.localOracle, order.inputs, abi.encode(order.outputs)));
    }

    function getCompactBatchWitnessSignature(
        bytes32 typeHash,
        address arbiter,
        CatalystCompactOrder memory order
    ) internal view returns (bytes memory sig) {
        bytes32 domainSeparator = THE_COMPACT.DOMAIN_SEPARATOR();
        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(typeHash, arbiter, order.user, order.nonce, order.fillDeadline, keccak256(abi.encodePacked(order.inputs)), orderWitnessHash(order)))));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint("PRIVATE_KEY"), msgHash);
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

    function signIntent(uint256 tokenId, uint256 inputAmount, address outToken, uint256 outputAmount, uint256 nonce, uint256 remoteChain) view external returns(bytes32 orderId, bytes memory sponsorSig) {
        // Manage Inputs
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, inputAmount];

        // Manage Outputs

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

    function fillOutput(bytes32 orderId, address token, uint256 amount, address recipient) external {
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteFiller: bytes32(uint256(uint160(address(COIN_FILLER)))),
            remoteOracle: bytes32(uint256(uint160(WORMHOLE_ORACLE[block.chainid]))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(token)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(recipient))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        if (ERC20(token).allowance(msg.sender, COIN_FILLER) < amount) ERC20(token).approve(COIN_FILLER, amount);

        bytes32 solverIdentifier = bytes32(uint256(uint160(msg.sender)));
        CoinFiller(COIN_FILLER).fill(orderId, outputs[0], solverIdentifier);


        bytes[] memory payloads = new bytes[](1);
        payloads[0] = OutputEncodingLib.encodeFillDescriptionM(solverIdentifier, orderId, uint32(block.timestamp), outputs[0]);
        WormholeOracle(WORMHOLE_ORACLE[block.chainid]).submit(COIN_FILLER, payloads);
    }
}
