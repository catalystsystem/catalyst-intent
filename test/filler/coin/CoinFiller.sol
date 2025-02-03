// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import { CoinFiller } from "../../../src/reactors/filler/CoinFiller.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { OutputDescription } from "../../../src/reactors/CatalystOrderType.sol";

contract TestCoinFiller is Test {
    error ZeroValue();  
    error WrongChain(uint256 expected, uint256 actual);
    error WrongRemoteOracle(bytes32 addressThis, bytes32 expected);

    CoinFiller coinFiller;

    MockERC20 outputToken;

    address swapper;
    address solver;

    function setUp() public {
        coinFiller = new CoinFiller();
        outputToken = new MockERC20("TEST", "TEST", 18);

        swapper = makeAddr("swapper");
        solver = makeAddr("solver");
    }

    // --- VALID CASES --- //
    function test_fill_skip() public {

    }

    // --- FAILURE CASES --- //
    
    function test_fill_throw_zero_filler(address sender, bytes32 orderId) public {
        bytes32[] memory  orderIds = new bytes32[](1);
        OutputDescription[] memory outputs = new OutputDescription[](1);
        bytes32 filler = bytes32(0);

        orderIds[0] = orderId;
        outputs[0] = OutputDescription({
            remoteOracle: bytes32(0),
            chainId: 0,
            token: bytes32(0),
            amount: 0,
            recipient: bytes32(0),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        vm.expectRevert(ZeroValue.selector);
        vm.prank(sender);
        coinFiller.fillThrow(orderIds, outputs, filler);
    }

    function test_fill_skip_zero_filler(address sender, bytes32 orderId) public {
        bytes32[] memory  orderIds = new bytes32[](1);
        OutputDescription[] memory outputs = new OutputDescription[](1);
        bytes32 filler = bytes32(0);

        orderIds[0] = orderId;
        outputs[0] = OutputDescription({
            remoteOracle: bytes32(0),
            chainId: 0,
            token: bytes32(0),
            amount: 0,
            recipient: bytes32(0),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        vm.expectRevert(ZeroValue.selector);
        vm.prank(sender);
        coinFiller.fillSkip(orderIds, outputs, filler);
    }

    function test_invalid_chain_id(address sender, bytes32 filler, bytes32 orderId, uint256 chainId) public {
        vm.assume(chainId != block.chainid);
        vm.assume(filler != bytes32(0));

        bytes32[] memory  orderIds = new bytes32[](1);
        OutputDescription[] memory outputs = new OutputDescription[](1);

        orderIds[0] = orderId;
        outputs[0] = OutputDescription({
            remoteOracle: bytes32(0),
            chainId: chainId,
            token: bytes32(0),
            amount: 0,
            recipient: bytes32(0),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(WrongChain.selector, block.chainid, chainId));
        vm.prank(sender);
        coinFiller.fillSkip(orderIds, outputs, filler);
    }

    function test_invalid_oracle(address sender, bytes32 filler, bytes32 orderId, bytes32 oracle) public {
        bytes16 fillerOracleBytes = bytes16(oracle) << 8;
        bytes16 coinFillerOracleBytes = bytes16(uint128(uint160(address(coinFiller)))) << 8;

        vm.assume(fillerOracleBytes != coinFillerOracleBytes);
        vm.assume(filler != bytes32(0));

        bytes32[] memory  orderIds = new bytes32[](1);
        OutputDescription[] memory outputs = new OutputDescription[](1);

        orderIds[0] = orderId;
        outputs[0] = OutputDescription({
            remoteOracle: oracle,
            chainId: block.chainid,
            token: bytes32(0),
            amount: 0,
            recipient: bytes32(0),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(WrongRemoteOracle.selector, coinFillerOracleBytes, fillerOracleBytes));
        vm.prank(sender);
        coinFiller.fillSkip(orderIds, outputs, filler);
    }     

}
