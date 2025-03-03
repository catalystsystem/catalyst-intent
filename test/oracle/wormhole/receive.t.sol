// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.22;

import { WormholeOracle } from "src/oracles/wormhole/WormholeOracle.sol";
import { TestWormholeCallWorm } from "./callworm.t.sol";

contract TestReceiveWormholeOracleProofs is TestWormholeCallWorm {
    event OutputProven(uint256 chainid, bytes32 remoteIdentifier, bytes32 application, bytes32 payloadHash);

    WormholeOracle oracle;

    function test_receive_proof() external {
        oracle = new WormholeOracle(address(this), address(messages));
        bytes memory stripped_message = hex"1611edd9a9d42dbcd9ae773ffa22be0f6017b00590959dd5c767e4efcd34cd0b000100b400000000000000000000000000000000000000000000000000000000000000ac82f523c28a9556fdc958116e496b8ce488969b8ffbb8998620c5e890c6156cf5000000005ef2fcf809fb9535ea0aeaea421f683026f06c34569aafc42bcde652ef6dd270640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ec191e4700000000000000000000000000000000";
        bytes memory validVM = makeValidVM(stripped_message);
        bytes32 payloadHash = keccak256(hex"00000000000000000000000000000000000000000000000000000000000000ac82f523c28a9556fdc958116e496b8ce488969b8ffbb8998620c5e890c6156cf5000000005ef2fcf809fb9535ea0aeaea421f683026f06c34569aafc42bcde652ef6dd270640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ec191e4700000000000000000000000000000000");

        vm.prank(address(this));
        oracle.setChainMap(13, 13);
        /**
            chainId: 13(00x000d)
            remoteIdentifier: 0xdeadbeefbeefdead
            application: 0x1611edd9a9d42dbcd9ae773ffa22be0f6017b00590959dd5c767e4efcd34cd0b
            payload: 00000000000000000000000000000000000000000000000000000000000000ac82f523c28a9556fdc958116e496b8ce488969b8ffbb8998620c5e890c6156cf5000000005ef2fcf809fb9535ea0aeaea421f683026f06c34569aafc42bcde652ef6dd270640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ec191e4700000000000000000000000000000000

            The chainId and remoteIdentifier are from the oracle with dummy guardian set.
            The application is the coin_filler id from fill_and_submit test in SUI.
            The payload is the fill description from the fill_and_submit test in SUI.
         */
        
        vm.expectEmit();
        emit OutputProven(13, bytes32(uint256(0xdeadbeefbeefdead)), 0x1611edd9a9d42dbcd9ae773ffa22be0f6017b00590959dd5c767e4efcd34cd0b, payloadHash);

        oracle.receiveMessage(validVM);
        assert(oracle.isProven(13, bytes32(uint256(0xdeadbeefbeefdead)), 0x1611edd9a9d42dbcd9ae773ffa22be0f6017b00590959dd5c767e4efcd34cd0b, payloadHash));
    }
}