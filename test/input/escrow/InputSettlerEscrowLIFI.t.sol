// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import { InputSettlerEscrowLIFI } from "../../../src/input/escrow/InputSettlerEscrowLIFI.sol";

import { StandardOrder } from "OIF/src/input/types/StandardOrderType.sol";
import { MandateOutput, MandateOutputEncodingLib } from "OIF/src/libs/MandateOutputEncodingLib.sol";

import { InputSettlerEscrowTest } from "OIF/test/input/escrow/InputSettlerEscrow.t.sol";

contract InputSettlerEscrowLIFIHarness is InputSettlerEscrowLIFI {
    constructor(
        address initialOwner
    ) InputSettlerEscrowLIFI(initialOwner) { }

    function validateFillsNow(address inputOracle, MandateOutput[] calldata outputs, bytes32 orderId) external view {
        _validateFillsNow(inputOracle, outputs, orderId);
    }
}

contract inputSettlerEscrowTestBaseLIFI is InputSettlerEscrowTest {
    function setUp() public virtual override {
        super.setUp();

        owner = makeAddr("owner");
        inputSettlerEscrow = address(new InputSettlerEscrowLIFIHarness(owner));
    }

    struct OrderFulfillmentDescription {
        uint32 timestamp;
        MandateOutput MandateOutput;
    }

    function test_validate_fills_now(
        bytes32 orderId,
        address callerOfContract,
        OrderFulfillmentDescription[] calldata orderFulfillmentDescription
    ) external {
        vm.assume(orderFulfillmentDescription.length > 0);

        bytes memory expectedProofPayload = hex"";
        uint32[] memory timestamps = new uint32[](orderFulfillmentDescription.length);
        MandateOutput[] memory mandateOutputs = new MandateOutput[](orderFulfillmentDescription.length);
        for (uint256 i; i < orderFulfillmentDescription.length; ++i) {
            timestamps[i] = orderFulfillmentDescription[i].timestamp;
            mandateOutputs[i] = orderFulfillmentDescription[i].MandateOutput;
            MandateOutput memory output = mandateOutputs[i];

            expectedProofPayload = abi.encodePacked(
                expectedProofPayload,
                output.chainId,
                output.oracle,
                output.settler,
                keccak256(
                    MandateOutputEncodingLib.encodeFillDescriptionMemory(
                        bytes32(uint256(uint160(callerOfContract))),
                        orderId,
                        uint32(block.timestamp),
                        output.token,
                        output.amount,
                        output.recipient,
                        output.call,
                        output.context
                    )
                )
            );
        }
        _validProofSeries[expectedProofPayload] = true;

        vm.prank(callerOfContract);
        InputSettlerEscrowLIFIHarness(inputSettlerEscrow).validateFillsNow(address(this), mandateOutputs, orderId);
    }

    // --- Fee tests --- //

    function test_invalid_governance_fee() public {
        vm.prank(owner);
        InputSettlerEscrowLIFI(inputSettlerEscrow).setGovernanceFee(MAX_GOVERNANCE_FEE);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        InputSettlerEscrowLIFI(inputSettlerEscrow).setGovernanceFee(MAX_GOVERNANCE_FEE + 1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        InputSettlerEscrowLIFI(inputSettlerEscrow).setGovernanceFee(MAX_GOVERNANCE_FEE + 123123123);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        InputSettlerEscrowLIFI(inputSettlerEscrow).setGovernanceFee(type(uint64).max);
    }

    function test_governance_fee_change_not_ready(uint64 fee, uint256 timeDelay) public {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.assume(timeDelay < uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);

        vm.prank(owner);
        vm.expectEmit();
        emit NextGovernanceFee(fee, uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);
        InputSettlerEscrowLIFI(inputSettlerEscrow).setGovernanceFee(fee);

        vm.warp(timeDelay);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeChangeNotReady()"));
        InputSettlerEscrowLIFI(inputSettlerEscrow).applyGovernanceFee();

        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);

        assertEq(InputSettlerEscrowLIFI(inputSettlerEscrow).governanceFee(), 0);

        vm.expectEmit();
        emit GovernanceFeeChanged(0, fee);
        InputSettlerEscrowLIFI(inputSettlerEscrow).applyGovernanceFee();

        assertEq(InputSettlerEscrowLIFI(inputSettlerEscrow).governanceFee(), fee);
    }

    /// forge-config: default.isolate = true
    function test_finalise_self_with_fee_gas() public {
        test_finalise_self_with_fee(MAX_GOVERNANCE_FEE / 3);
    }

    function test_finalise_self_with_fee(
        uint64 fee
    ) public {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.prank(owner);
        InputSettlerEscrowLIFI(inputSettlerEscrow).setGovernanceFee(fee);
        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);
        InputSettlerEscrowLIFI(inputSettlerEscrow).applyGovernanceFee();

        uint256 amount = 1e18 / 10;
        address inputOracle = address(alwaysYesOracle);

        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = MandateOutput({
            settler: bytes32(uint256(uint160(address(outputSettlerCoin)))),
            oracle: bytes32(uint256(uint160(inputOracle))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            call: hex"",
            context: hex""
        });
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        StandardOrder memory order = StandardOrder({
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            expires: type(uint32).max,
            fillDeadline: type(uint32).max,
            inputOracle: inputOracle,
            inputs: inputs,
            outputs: outputs
        });

        // Deposit into the escrow
        vm.prank(swapper);
        token.approve(inputSettlerEscrow, amount);
        vm.prank(swapper);
        InputSettlerEscrowLIFI(inputSettlerEscrow).open(abi.encode(order));

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        bytes32 orderId = InputSettlerEscrowLIFI(inputSettlerEscrow).orderIdentifier(order);
        bytes memory payload = MandateOutputEncodingLib.encodeFillDescriptionMemory(
            bytes32(uint256(uint160((solver)))), orderId, uint32(block.timestamp), outputs[0]
        );
        bytes32 payloadHash = keccak256(payload);

        vm.expectCall(
            address(alwaysYesOracle),
            abi.encodeWithSignature(
                "efficientRequireProven(bytes)",
                abi.encodePacked(
                    order.outputs[0].chainId, order.outputs[0].oracle, order.outputs[0].settler, payloadHash
                )
            )
        );

        bytes32[] memory solvers = new bytes32[](1);
        solvers[0] = bytes32(uint256(uint160((solver))));

        vm.prank(solver);
        InputSettlerEscrowLIFI(inputSettlerEscrow).finalise(
            order, timestamps, solvers, bytes32(uint256(uint160((solver)))), hex""
        );
        vm.snapshotGasLastCall("inputSettler", "escrowFinaliseSelfWithFee");

        uint256 govFeeAmount = (amount * fee) / 10 ** 18;
        uint256 amountPostFee = amount - govFeeAmount;

        assertEq(token.balanceOf(solver), amountPostFee);
        assertEq(token.balanceOf(InputSettlerEscrowLIFI(inputSettlerEscrow).owner()), govFeeAmount);
    }
}
