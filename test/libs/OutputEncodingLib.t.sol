// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { OutputDescription, OutputEncodingLib } from "src/libs/OutputEncodingLib.sol";

contract OutputEncodingLibTest is Test {
    function encodeOutputDescriptionHarness(
        OutputDescription calldata outputDescription
    ) external pure returns (bytes memory encodedOutput) {
        return OutputEncodingLib.encodeOutputDescription(outputDescription);
    }

    function encodeOutputDescriptionMemoryHarness(
        OutputDescription memory outputDescription
    ) external pure returns (bytes memory encodedOutput) {
        return OutputEncodingLib.encodeOutputDescriptionMemory(outputDescription);
    }

    function encodeFillDescriptionHarness(
        bytes32 solver,
        bytes32 orderId,
        uint32 timestamp,
        bytes32 token,
        uint256 amount,
        bytes32 recipient,
        bytes memory remoteCall,
        bytes memory fulfillmentContext
    ) external pure returns (bytes memory encodedOutput) {
        return OutputEncodingLib.encodeFillDescription(
            solver, orderId, timestamp, token, amount, recipient, remoteCall, fulfillmentContext
        );
    }

    function encodeFillDescriptionHarness(
        bytes32 solver,
        bytes32 orderId,
        uint32 timestamp,
        OutputDescription calldata outputDescription
    ) external pure returns (bytes memory encodedOutput) {
        return OutputEncodingLib.encodeFillDescription(solver, orderId, timestamp, outputDescription);
    }

    function encodeFillDescriptionMemoryHarness(
        bytes32 solver,
        bytes32 orderId,
        uint32 timestamp,
        OutputDescription memory outputDescription
    ) external pure returns (bytes memory encodedOutput) {
        return OutputEncodingLib.encodeFillDescriptionM(solver, orderId, timestamp, outputDescription);
    }

    function test_encodeOutputDescription() external view {
        // The goal of this output is to fill all bytes such that no bytes are left empty.
        // This allows for better comparision to other vm implementations incase something is wrong.
        OutputDescription memory outputDescription = OutputDescription({
            remoteOracle: keccak256(bytes("remoteOracle")),
            remoteFiller: keccak256(bytes("remoteFiller")),
            chainId: uint256(keccak256(bytes("chainId"))),
            token: keccak256(bytes("token")),
            amount: uint256(keccak256(bytes("amount"))),
            recipient: keccak256(bytes("recipient")),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });

        bytes memory encodedOutput = this.encodeOutputDescriptionHarness(outputDescription);
        bytes memory encodedOutputMemory = this.encodeOutputDescriptionMemoryHarness(outputDescription);
        assertEq(encodedOutput, encodedOutputMemory);
        assertEq(
            encodedOutput,
            hex"2e7527e20e9b97ff3a5ce16d17d50dd1fac8c30234ec6b506d9f3432963d59eaeea9f5c15a2df2f14967c00454f81ca23160413d9481e50c2858985720af91e18ed9144e2f2122812934305f889c544efe55db33a5fd4b235aaab787c3f913d49b9b0454cadcb5884dd3faa6ba975da4d2459aa3f11d31291a25a8358f84946d89c4783cb6cc307f98e95f2d5d5d8647bdb3d4bdd087209374f187b38e098895811085f5b5d1b29598e73ca51de3d712f5d3103ad50e22dc1f4d3ff1559d511500000000"
        );

        outputDescription.remoteCall = abi.encodePacked(keccak256(hex""), keccak256(hex"01"), bytes3(0x010203));
        outputDescription.fulfillmentContext = abi.encodePacked(
            keccak256(hex"02"), keccak256(hex"03"), keccak256(hex"04"), keccak256(hex"05"), bytes4(0x01020304)
        );

        encodedOutput = this.encodeOutputDescriptionHarness(outputDescription);
        encodedOutputMemory = this.encodeOutputDescriptionMemoryHarness(outputDescription);
        assertEq(encodedOutput, encodedOutputMemory);
        assertEq(
            encodedOutput,
            hex"2e7527e20e9b97ff3a5ce16d17d50dd1fac8c30234ec6b506d9f3432963d59eaeea9f5c15a2df2f14967c00454f81ca23160413d9481e50c2858985720af91e18ed9144e2f2122812934305f889c544efe55db33a5fd4b235aaab787c3f913d49b9b0454cadcb5884dd3faa6ba975da4d2459aa3f11d31291a25a8358f84946d89c4783cb6cc307f98e95f2d5d5d8647bdb3d4bdd087209374f187b38e098895811085f5b5d1b29598e73ca51de3d712f5d3103ad50e22dc1f4d3ff1559d51150043c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a4705fe7f977e71dba2ea1a68e21057beebb9be2ac30c6410aa38d4f3fbe41dcffd20102030084f2ee15ea639b73fa3db9b34a245bdfa015c260c598b211bf05a1ecc4b3e3b4f269c322e3248a5dfc29d73c5b0553b0185a35cd5bb6386747517ef7e53b15e287f343681465b9efe82c933c3e8748c70cb8aa06539c361de20f72eac04e766393dbb8d0f4c497851a5043c6363657698cb1387682cac2f786c731f8936109d79501020304"
        );
    }

    function test_revert_encodeOutputDescription_RemoteCallOutOfRange() external {
        OutputDescription memory outputDescription = OutputDescription({
            remoteOracle: keccak256(bytes("remoteOracle")),
            remoteFiller: keccak256(bytes("remoteFiller")),
            chainId: uint256(keccak256(bytes("chainId"))),
            token: keccak256(bytes("token")),
            amount: uint256(keccak256(bytes("amount"))),
            recipient: keccak256(bytes("recipient")),
            remoteCall: new bytes(65535 - 1),
            fulfillmentContext: new bytes(0)
        });

        this.encodeOutputDescriptionHarness(outputDescription);
        this.encodeOutputDescriptionMemoryHarness(outputDescription);

        outputDescription.remoteCall = new bytes(65536);

        vm.expectRevert(abi.encodeWithSignature("RemoteCallOutOfRange()"));
        this.encodeOutputDescriptionHarness(outputDescription);
        vm.expectRevert(abi.encodeWithSignature("RemoteCallOutOfRange()"));
        this.encodeOutputDescriptionMemoryHarness(outputDescription);
    }

    function test_revert_encodeOutputDescription_FulfillmentContextCallOutOfRange() external {
        OutputDescription memory outputDescription = OutputDescription({
            remoteOracle: keccak256(bytes("remoteOracle")),
            remoteFiller: keccak256(bytes("remoteFiller")),
            chainId: uint256(keccak256(bytes("chainId"))),
            token: keccak256(bytes("token")),
            amount: uint256(keccak256(bytes("amount"))),
            recipient: keccak256(bytes("recipient")),
            remoteCall: new bytes(0),
            fulfillmentContext: new bytes(65535 - 1)
        });

        this.encodeOutputDescriptionHarness(outputDescription);
        this.encodeOutputDescriptionMemoryHarness(outputDescription);

        outputDescription.fulfillmentContext = new bytes(65536);

        vm.expectRevert(abi.encodeWithSignature("FulfillmentContextCallOutOfRange()"));
        this.encodeOutputDescriptionHarness(outputDescription);
        vm.expectRevert(abi.encodeWithSignature("FulfillmentContextCallOutOfRange()"));
        this.encodeOutputDescriptionMemoryHarness(outputDescription);
    }

    function test_encodeFillDescription() external view {
        // The goal of this output is to fill all bytes such that no bytes are left empty.
        // This allows for better comparision to other vm implementations incase something is wrong.
        bytes32 solver = keccak256(bytes("solver"));
        bytes32 orderId = keccak256(bytes("orderId"));
        uint32 timestamp = uint32(uint256(keccak256(bytes("timestamp"))));
        bytes32 token = keccak256(bytes("token"));
        uint256 amount = uint256(keccak256(bytes("amount")));
        bytes32 recipient = keccak256(bytes("recipient"));
        bytes memory remoteCall = hex"";
        bytes memory fulfillmentContext = hex"";

        OutputDescription memory outputDescription = OutputDescription({
            remoteOracle: keccak256(bytes("remoteOracle")),
            remoteFiller: keccak256(bytes("remoteFiller")),
            chainId: uint256(keccak256(bytes("chainId"))),
            token: token,
            amount: amount,
            recipient: recipient,
            remoteCall: remoteCall,
            fulfillmentContext: fulfillmentContext
        });

        bytes memory encodedOutputFromOutput =
            this.encodeFillDescriptionHarness(solver, orderId, timestamp, outputDescription);
        bytes memory encodedOutputFromOutputMemory =
            this.encodeFillDescriptionMemoryHarness(solver, orderId, timestamp, outputDescription);
        bytes memory encodedOutput = this.encodeFillDescriptionHarness(
            solver, orderId, timestamp, token, amount, recipient, remoteCall, fulfillmentContext
        );
        assertEq(encodedOutputFromOutput, encodedOutputFromOutputMemory);
        assertEq(encodedOutputFromOutput, encodedOutput);
        assertEq(
            encodedOutputFromOutput,
            hex"1da5212527b611fa26a679f652ca82511b7def2f4c7af4d7bb6f175835f323dcaad60a3265e1c3c0dff4ef3474d6c608ca5f7ec61bd7dcbc5a992ad0576306911227958e9b9b0454cadcb5884dd3faa6ba975da4d2459aa3f11d31291a25a8358f84946d89c4783cb6cc307f98e95f2d5d5d8647bdb3d4bdd087209374f187b38e098895811085f5b5d1b29598e73ca51de3d712f5d3103ad50e22dc1f4d3ff1559d511500000000"
        );

        remoteCall = abi.encodePacked(keccak256(hex""), keccak256(hex"01"), bytes3(0x010203));
        outputDescription.remoteCall = remoteCall;
        fulfillmentContext = abi.encodePacked(
            keccak256(hex"02"), keccak256(hex"03"), keccak256(hex"04"), keccak256(hex"05"), bytes4(0x01020304)
        );
        outputDescription.fulfillmentContext = fulfillmentContext;

        encodedOutputFromOutput = this.encodeFillDescriptionHarness(solver, orderId, timestamp, outputDescription);
        encodedOutputFromOutputMemory =
            this.encodeFillDescriptionMemoryHarness(solver, orderId, timestamp, outputDescription);
        encodedOutput = this.encodeFillDescriptionHarness(
            solver, orderId, timestamp, token, amount, recipient, remoteCall, fulfillmentContext
        );
        assertEq(encodedOutputFromOutput, encodedOutputFromOutputMemory);
        assertEq(encodedOutputFromOutput, encodedOutput);
        assertEq(
            encodedOutputFromOutput,
            hex"1da5212527b611fa26a679f652ca82511b7def2f4c7af4d7bb6f175835f323dcaad60a3265e1c3c0dff4ef3474d6c608ca5f7ec61bd7dcbc5a992ad0576306911227958e9b9b0454cadcb5884dd3faa6ba975da4d2459aa3f11d31291a25a8358f84946d89c4783cb6cc307f98e95f2d5d5d8647bdb3d4bdd087209374f187b38e098895811085f5b5d1b29598e73ca51de3d712f5d3103ad50e22dc1f4d3ff1559d51150043c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a4705fe7f977e71dba2ea1a68e21057beebb9be2ac30c6410aa38d4f3fbe41dcffd20102030084f2ee15ea639b73fa3db9b34a245bdfa015c260c598b211bf05a1ecc4b3e3b4f269c322e3248a5dfc29d73c5b0553b0185a35cd5bb6386747517ef7e53b15e287f343681465b9efe82c933c3e8748c70cb8aa06539c361de20f72eac04e766393dbb8d0f4c497851a5043c6363657698cb1387682cac2f786c731f8936109d79501020304"
        );
    }

    function test_revert_encodeFillDescription_RemoteCallOutOfRange() external {
        bytes32 solver = keccak256(bytes("solver"));
        bytes32 orderId = keccak256(bytes("orderId"));
        uint32 timestamp = uint32(uint256(keccak256(bytes("timestamp"))));
        bytes32 token = keccak256(bytes("token"));
        uint256 amount = uint256(keccak256(bytes("amount")));
        bytes32 recipient = keccak256(bytes("recipient"));
        bytes memory remoteCall = new bytes(65536 - 1);
        bytes memory fulfillmentContext = hex"";

        OutputDescription memory outputDescription = OutputDescription({
            remoteOracle: keccak256(bytes("remoteOracle")),
            remoteFiller: keccak256(bytes("remoteFiller")),
            chainId: uint256(keccak256(bytes("chainId"))),
            token: token,
            amount: amount,
            recipient: recipient,
            remoteCall: remoteCall,
            fulfillmentContext: fulfillmentContext
        });

        this.encodeFillDescriptionHarness(solver, orderId, timestamp, outputDescription);
        this.encodeFillDescriptionMemoryHarness(solver, orderId, timestamp, outputDescription);
        this.encodeFillDescriptionHarness(
            solver, orderId, timestamp, token, amount, recipient, remoteCall, fulfillmentContext
        );

        remoteCall = new bytes(65536);
        outputDescription.remoteCall = remoteCall;

        vm.expectRevert(abi.encodeWithSignature("RemoteCallOutOfRange()"));
        this.encodeFillDescriptionHarness(solver, orderId, timestamp, outputDescription);
        vm.expectRevert(abi.encodeWithSignature("RemoteCallOutOfRange()"));
        this.encodeFillDescriptionMemoryHarness(solver, orderId, timestamp, outputDescription);
        vm.expectRevert(abi.encodeWithSignature("RemoteCallOutOfRange()"));
        this.encodeFillDescriptionHarness(
            solver, orderId, timestamp, token, amount, recipient, remoteCall, fulfillmentContext
        );
    }

    function test_revert_encodeFillDescription_FulfillmentContextCallOutOfRange() external {
        bytes32 solver = keccak256(bytes("solver"));
        bytes32 orderId = keccak256(bytes("orderId"));
        uint32 timestamp = uint32(uint256(keccak256(bytes("timestamp"))));
        bytes32 token = keccak256(bytes("token"));
        uint256 amount = uint256(keccak256(bytes("amount")));
        bytes32 recipient = keccak256(bytes("recipient"));
        bytes memory remoteCall = hex"";
        bytes memory fulfillmentContext = new bytes(65536 - 1);

        OutputDescription memory outputDescription = OutputDescription({
            remoteOracle: keccak256(bytes("remoteOracle")),
            remoteFiller: keccak256(bytes("remoteFiller")),
            chainId: uint256(keccak256(bytes("chainId"))),
            token: token,
            amount: amount,
            recipient: recipient,
            remoteCall: remoteCall,
            fulfillmentContext: fulfillmentContext
        });

        this.encodeFillDescriptionHarness(solver, orderId, timestamp, outputDescription);
        this.encodeFillDescriptionMemoryHarness(solver, orderId, timestamp, outputDescription);
        this.encodeFillDescriptionHarness(
            solver, orderId, timestamp, token, amount, recipient, remoteCall, fulfillmentContext
        );

        fulfillmentContext = new bytes(65536);
        outputDescription.fulfillmentContext = fulfillmentContext;

        vm.expectRevert(abi.encodeWithSignature("FulfillmentContextCallOutOfRange()"));
        this.encodeFillDescriptionHarness(solver, orderId, timestamp, outputDescription);
        vm.expectRevert(abi.encodeWithSignature("FulfillmentContextCallOutOfRange()"));
        this.encodeFillDescriptionMemoryHarness(solver, orderId, timestamp, outputDescription);
        vm.expectRevert(abi.encodeWithSignature("FulfillmentContextCallOutOfRange()"));
        this.encodeFillDescriptionHarness(
            solver, orderId, timestamp, token, amount, recipient, remoteCall, fulfillmentContext
        );
    }
}
