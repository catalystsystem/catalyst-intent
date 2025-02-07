pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { CoinFillerWithFee } from "../../../src/fillers/coin/CoinFillerWithFee.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { OutputDescription } from "../../../src/libs/OutputEncodingLib.sol";

contract TestCoinFillerWithFee is Test {
    error GovernanceFeeTooHigh();
    error GovernanceFeeChangeNotReady();

    event NextGovernanceFee(uint64 nextGovernanceFee, uint64 nextGovernanceFeeTime);
    event GovernanceFeeChanged(uint64 oldGovernanceFee, uint64 newGovernanceFee);
    event OutputFilled(bytes32 orderId, bytes32 solver, uint32 timestamp, OutputDescription output);
    event GovernanceFeesDistributed(address indexed to, address[] tokens, uint256[] collectedAmounts);


    CoinFillerWithFee coinFillerWithFee;

    MockERC20 outputToken;

    address swapper;
    address owner;
    address coinFillerWithFeeAddress;
    address outputTokenAddress;

    uint256 constant MAX_GOVERNANCE_FEE = 10 ** 18 * 0.1; // 10%
    uint64 constant GOVERNANCE_FEE_CHANGE_DELAY = 7 days;
    uint256 constant GOVERNANCE_FEE_DENOM = 10 ** 18;

    function setUp() public {
        owner = makeAddr("owner");

        coinFillerWithFee = new CoinFillerWithFee(owner);
        outputToken = new MockERC20("TEST", "TEST", 18);

        swapper = makeAddr("swapper");
        coinFillerWithFeeAddress = address(coinFillerWithFee);
        outputTokenAddress = address(outputToken);
    }

    // --- VALID CASES --- //

    function test_fees_with_entire_flow(bytes32 orderId, address sender, bytes32 filler, uint64 fee, uint64 timeDelay, uint128 amount) public {
        vm.assume(fee <= MAX_GOVERNANCE_FEE && fee != 0);
        vm.assume(timeDelay > uint64(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);
        vm.assume(filler != bytes32(0) && sender != swapper);

        uint256 expectedGovernanceShare = uint256(amount) * uint256(fee) / GOVERNANCE_FEE_DENOM;

        outputToken.mint(sender, amount + expectedGovernanceShare);
        vm.prank(sender);
        outputToken.approve(coinFillerWithFeeAddress, amount + expectedGovernanceShare);

        vm.prank(owner);
        vm.expectEmit();
        emit NextGovernanceFee(fee, uint64(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);
        coinFillerWithFee.setGovernanceFee(fee);

        vm.warp(timeDelay);
        vm.expectEmit();
        emit GovernanceFeeChanged(0, fee);
        coinFillerWithFee.applyGovernanceFee();

        OutputDescription[] memory outputs = new OutputDescription[](1);
        bytes16 fillerAddress = bytes16(uint128(uint160(coinFillerWithFeeAddress))) << 8;
        bytes32 remoteOracle = bytes32(fillerAddress) >> 8;

        outputs[0] = OutputDescription({
            remoteOracle: remoteOracle,
            chainId: block.chainid,
            token: bytes32(uint256(uint160(outputTokenAddress))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: bytes(""),
            fulfillmentContext: bytes("")
        });

        vm.prank(sender);
        vm.expectEmit();
        emit OutputFilled(orderId, filler, uint32(block.timestamp), outputs[0]);

        vm.expectCall(
            outputTokenAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, swapper, amount)
        );
        vm.expectCall(
            outputTokenAddress,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, coinFillerWithFeeAddress, expectedGovernanceShare)
        );

        coinFillerWithFee.fill(orderId, outputs[0], filler);

        assertEq(outputToken.balanceOf(swapper), amount);
        assertEq(outputToken.balanceOf(coinFillerWithFeeAddress), expectedGovernanceShare);
        assertEq(outputToken.balanceOf(sender), 0);
        assertEq(coinFillerWithFee.getGovernanceTokens(outputTokenAddress), expectedGovernanceShare);

        address governanceRecipient = makeAddr("governanceRecipient");
        address[] memory tokens = new address[](1);
        tokens[0] = outputTokenAddress;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = expectedGovernanceShare;

        vm.prank(owner);
        vm.expectEmit();
        emit GovernanceFeesDistributed(governanceRecipient, tokens, amounts);

        vm.expectCall(
            outputTokenAddress,
            abi.encodeWithSignature("transfer(address,uint256)", governanceRecipient, expectedGovernanceShare)
        );

        coinFillerWithFee.distributeGovernanceTokens(tokens, governanceRecipient);

        assertEq(outputToken.balanceOf(governanceRecipient), expectedGovernanceShare);
        assertEq(outputToken.balanceOf(coinFillerWithFeeAddress), 0);
    }


    // --- FAILURE CASES --- //

    function test_invalid_governance_fee(uint64 fee) public {
        vm.assume(fee > MAX_GOVERNANCE_FEE);
        
        vm.prank(owner);
        vm.expectRevert(GovernanceFeeTooHigh.selector);
        coinFillerWithFee.setGovernanceFee(fee);
    }

    function test_governance_fee_change_not_ready(uint64 fee, uint256 timeDelay) public {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.assume(timeDelay < uint64(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);
        
        vm.prank(owner);
        vm.expectEmit();
        emit NextGovernanceFee(fee, uint64(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);
        coinFillerWithFee.setGovernanceFee(fee);

        vm.warp(timeDelay);
        vm.expectRevert(GovernanceFeeChangeNotReady.selector);
        coinFillerWithFee.applyGovernanceFee();
    }
}