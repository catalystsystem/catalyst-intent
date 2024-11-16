// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.22;

import "../../../src/oracles/wormhole/external/wormhole/Messages.sol";
import "../../../src/oracles/wormhole/external/wormhole/Setters.sol";
import "../../../src/oracles/wormhole/external/wormhole/Structs.sol";
import { WormholeVerifier } from "../../../src/oracles/wormhole/external/callworm/WormholeVerifier.sol";
import { SmallStructs } from "../../../src/oracles/wormhole/external/callworm/SmallStructs.sol";
import "forge-std/Test.sol";

contract ExportedMessages is Messages, Setters {
    function storeGuardianSetPub(Structs.GuardianSet memory set, uint32 index) public {
        return super.storeGuardianSet(set, index);
    }
}

contract TestWormholeCallWorm is Test {

  bytes prevalidVM = hex"01" hex"00000000" hex"01";

  address testGuardianPub;
  uint256 testGuardian;

  ExportedMessages messages;

  WormholeVerifier verifier;

  Structs.GuardianSet guardianSet;

  function setUp() public {
    (testGuardianPub, testGuardian) = makeAddrAndKey("signer");

    messages = new ExportedMessages();

    verifier = new WormholeVerifier(address(messages));

    // initialize guardian set with one guardian
    address[] memory keys = new address[](1);
    keys[0] = vm.addr(testGuardian);
    guardianSet = Structs.GuardianSet(keys, 0);
    require(messages.quorum(guardianSet.keys.length) == 1, "Quorum should be 1");

    messages.storeGuardianSetPub(guardianSet, uint32(0));
  }

  function makeValidVM(bytes memory message) internal view returns(bytes memory validVM) {
    bytes memory postvalidVM = abi.encodePacked(buildPreMessage(0x000d, bytes32(uint256(0xdeadbeefbeefdead))), message);
    bytes32 vmHash = keccak256(abi.encodePacked(keccak256(postvalidVM)));
    (uint8 v, bytes32 r,  bytes32 s) = vm.sign(testGuardian, vmHash);

    validVM = abi.encodePacked(
      prevalidVM,
      uint8(0),
      r, s, v - 27,
      postvalidVM
    );
  }
  
  function buildPreMessage(uint16 emitterChainId, bytes32 emitterAddress) internal pure returns(bytes memory preMessage) {
    return abi.encodePacked(
        hex"000003e8" hex"00000001",
        emitterChainId,
        emitterAddress,
        hex"0000000000000539" hex"0f"
    );
  } 

  // This test checks the possibility of getting a unsigned message verified through verifyVM
  function test_compare_wormhole_implementation_and_calldata_version(bytes calldata message) public {
    bytes memory validVM = makeValidVM(message);
    // Confirm that the test VM is valid
    (Structs.VM memory parsedValidVm, bool valid, string memory reason) = messages.parseAndVerifyVM(validVM);
    (
      SmallStructs.SmallVM memory smallVM,
      bytes memory payload,
      bool valid2,
      string memory reason2
    ) = verifier.parseAndVerifyVM(validVM);
    
    require(valid, reason);
    assertEq(valid, true);
    assertEq(reason, "");

    assertEq(
      valid, valid2
    );
    assertEq(
      reason, reason2
    );

    assertEq(
      parsedValidVm.payload, payload, "payload"
    );
    assertEq(
      parsedValidVm.emitterChainId, smallVM.emitterChainId, "emitterChainId"
    );
    assertEq(
      parsedValidVm.emitterAddress, smallVM.emitterAddress, "emitterAddress"
    );
    assertEq(
      parsedValidVm.guardianSetIndex, smallVM.guardianSetIndex, "guardianSetIndex"
    );
  }

  function test_error_invalid_vm(bytes calldata message) public {
    bytes memory validVM = makeValidVM(message);
    bytes memory invalidVM = abi.encodePacked(validVM, uint8(1));

    // Confirm that the test VM is valid
    (, bool valid, string memory reason) = messages.parseAndVerifyVM(invalidVM);
    (
      ,
      ,
      bool valid2,
      string memory reason2
    ) = verifier.parseAndVerifyVM(invalidVM);
    

    assertEq(
      valid, valid2
    );
    assertEq(
      reason, reason2
    );

    assertEq(valid2, false);
    assertEq(reason2, "VM signature invalid");
  }
}
