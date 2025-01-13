// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { TheCompact } from "the-compact/src/TheCompact.sol";
import { AlwaysOKAllocator } from "the-compact/src/test/AlwaysOKAllocator.sol";


interface EIP712 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initializationCode) external payable returns (address deploymentAddress);
}

contract DeployCompact is Test {
    TheCompact public theCompact;
    uint256 allocatorPrivateKey;
    address allocator;
    bytes32 compactEIP712DomainHash = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 permit2EIP712DomainHash = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    address alwaysOKAllocator;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public virtual {
        theCompact = new TheCompact();

        (allocator, allocatorPrivateKey) = makeAddrAndKey("allocator");

        alwaysOKAllocator = address(new AlwaysOKAllocator());

        theCompact.__registerAllocator(alwaysOKAllocator, "");

        DOMAIN_SEPARATOR = EIP712(address(theCompact)).DOMAIN_SEPARATOR();
    }
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
}