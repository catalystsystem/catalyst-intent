// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { DeployPermit2 } from "permit2/test/utils/DeployPermit2.sol";

interface Permit2DomainSeparator {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract TestPermit2 is Test, DeployPermit2 {
    string public constant _PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";

    bytes32 private constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    address PERMIT2;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public virtual {
        PERMIT2 = deployPermit2();
        DOMAIN_SEPARATOR = Permit2DomainSeparator(PERMIT2).DOMAIN_SEPARATOR();
    }

    function test() external pure { }

    function getPermitBatchWitnessSignature(
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        uint256 privateKey,
        bytes32 typeHash,
        bytes32 witness,
        bytes32 domainSeparator,
        address sender
    ) internal pure returns (bytes memory sig) {
        bytes32[] memory tokenPermissions = new bytes32[](permit.permitted.length);
        for (uint256 i = 0; i < permit.permitted.length; ++i) {
            tokenPermissions[i] = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted[i]));
        }

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        typeHash,
                        keccak256(abi.encodePacked(tokenPermissions)),
                        sender,
                        permit.nonce,
                        permit.deadline,
                        witness
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }
}
