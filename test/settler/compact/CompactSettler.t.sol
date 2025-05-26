// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { LIFISettlerCompactWithDeposit } from "../../../src/settlers/compact/LIFISettlerCompactWithDeposit.sol";

import { SettlerCompactTest } from "OIF/test/settler/compact/SettlerCompact.t.sol";

import { MandateOutput, MandateOutputEncodingLib } from "OIF/src/libs/MandateOutputEncodingLib.sol";
import { StandardOrder } from "OIF/src/settlers/types/StandardOrderType.sol";

contract LIFISettlerCompactWithDepositHarness is LIFISettlerCompactWithDeposit {
    constructor(address compact, address initialOwner) LIFISettlerCompactWithDeposit(compact, initialOwner) { }

    function validateFills(
        StandardOrder calldata order,
        bytes32 orderId,
        bytes32[] calldata solvers,
        uint32[] calldata timestamps
    ) external view {
        _validateFills(order, orderId, solvers, timestamps);
    }

    function validateFills(
        StandardOrder calldata order,
        bytes32 orderId,
        bytes32 solver,
        uint32[] calldata timestamps
    ) external view {
        _validateFills(order, orderId, solver, timestamps);
    }
}

contract LIFISettlerCompactTest is SettlerCompactTest {
    // uint64 constant GOVERNANCE_FEE_CHANGE_DELAY = 7 days;
    // uint64 constant MAX_GOVERNANCE_FEE = 10 ** 18 * 0.05; // 10%

    function setUp() public override {
        super.setUp();

        owner = makeAddr("owner");
        settlerCompact = address(new LIFISettlerCompactWithDepositHarness(address(theCompact), owner));
    }

    // --- Fee tests --- //

    function test_invalid_governance_fee() public {
        vm.prank(owner);
        LIFISettlerCompactWithDepositHarness(settlerCompact).setGovernanceFee(MAX_GOVERNANCE_FEE);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        LIFISettlerCompactWithDepositHarness(settlerCompact).setGovernanceFee(MAX_GOVERNANCE_FEE + 1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        LIFISettlerCompactWithDepositHarness(settlerCompact).setGovernanceFee(MAX_GOVERNANCE_FEE + 123123123);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        LIFISettlerCompactWithDepositHarness(settlerCompact).setGovernanceFee(type(uint64).max);
    }

    function test_governance_fee_change_not_ready(uint64 fee, uint256 timeDelay) public {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.assume(timeDelay < uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);

        vm.prank(owner);
        vm.expectEmit();
        emit NextGovernanceFee(fee, uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);
        LIFISettlerCompactWithDepositHarness(settlerCompact).setGovernanceFee(fee);

        vm.warp(timeDelay);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeChangeNotReady()"));
        LIFISettlerCompactWithDepositHarness(settlerCompact).applyGovernanceFee();

        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);

        assertEq(LIFISettlerCompactWithDepositHarness(settlerCompact).governanceFee(), 0);

        vm.expectEmit();
        emit GovernanceFeeChanged(0, fee);
        LIFISettlerCompactWithDepositHarness(settlerCompact).applyGovernanceFee();

        assertEq(LIFISettlerCompactWithDepositHarness(settlerCompact).governanceFee(), fee);
    }

    /// forge-config: default.isolate = true
    function test_finalise_self_with_fee_gas() external {
        test_finalise_self_with_fee(MAX_GOVERNANCE_FEE / 3);
    }

    function test_finalise_self_with_fee(
        uint64 fee
    ) public {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.prank(owner);
        LIFISettlerCompactWithDepositHarness(settlerCompact).setGovernanceFee(fee);
        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);
        LIFISettlerCompactWithDepositHarness(settlerCompact).applyGovernanceFee();

        uint256 amount = 1e18 / 10;

        token.mint(swapper, amount);
        vm.prank(swapper);
        token.approve(address(theCompact), type(uint256).max);

        vm.prank(swapper);
        uint256 tokenId = theCompact.depositERC20(address(token), alwaysOkAllocatorLockTag, amount, swapper);

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [tokenId, amount];
        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = MandateOutput({
            remoteFiller: bytes32(uint256(uint160(address(coinFiller)))),
            remoteOracle: bytes32(uint256(uint160(address(alwaysYesOracle)))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        StandardOrder memory order = StandardOrder({
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            fillDeadline: type(uint32).max,
            expires: type(uint32).max,
            localOracle: alwaysYesOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Make Compact
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(
            swapperPrivateKey, settlerCompact, swapper, 0, type(uint32).max, idsAndAmounts, witnessHash(order)
        );

        bytes memory signature = abi.encode(sponsorSig, hex"");

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        uint256 govFeeAmount = amount * fee / 10 ** 18;
        uint256 amountPostFee = amount - govFeeAmount;

        vm.prank(solver);
        LIFISettlerCompactWithDepositHarness(settlerCompact).finaliseSelf(
            order, signature, timestamps, bytes32(uint256(uint160((solver))))
        );
        vm.snapshotGasLastCall("settler", "CompactFinaliseSelfWithFee");

        assertEq(token.balanceOf(solver), amountPostFee);
        assertEq(theCompact.balanceOf(owner, tokenId), govFeeAmount);
    }
}
