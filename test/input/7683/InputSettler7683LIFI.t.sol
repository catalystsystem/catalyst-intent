// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import { InputSettler7683LIFI } from "../../../src/input/7683/InputSettler7683LIFI.sol";

import { OnchainCrossChainOrder } from "OIF/src/interfaces/IERC7683.sol";

import { MandateERC7683 } from "OIF/src/input/7683/Order7683Type.sol";
import { StandardOrder } from "OIF/src/input/types/StandardOrderType.sol";
import { MandateOutput, MandateOutputEncodingLib } from "OIF/src/libs/MandateOutputEncodingLib.sol";

import { InputSettler7683Test } from "OIF/test/input/7683/InputSettler7683.t.sol";

contract InputSettler7683LIFIHarness is InputSettler7683LIFI {
    constructor(
        address initialOwner
    ) InputSettler7683LIFI(initialOwner) { }

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

    function validateFills(address localOracle, bytes32 orderId, MandateOutput[] memory outputs) external view {
        _validateFills(localOracle, orderId, outputs);
    }
}

contract InputSettler7683TestBaseLIFI is InputSettler7683Test {
    function setUp() public virtual override {
        super.setUp();

        owner = makeAddr("owner");
        inputsettler7683 = address(new InputSettler7683LIFIHarness(owner));
    }

    function test_validate_fills_now(
        bytes32 orderId,
        address callerOfContract,
        OrderFulfillmentDescription[] calldata orderFulfillmentDescription
    ) external {
        vm.assume(orderFulfillmentDescription.length > 0);

        bytes memory expectedProofPayload = hex"";
        uint32[] memory timestamps = new uint32[](orderFulfillmentDescription.length);
        MandateOutput[] memory MandateOutputs = new MandateOutput[](orderFulfillmentDescription.length);
        for (uint256 i; i < orderFulfillmentDescription.length; ++i) {
            timestamps[i] = orderFulfillmentDescription[i].timestamp;
            MandateOutputs[i] = orderFulfillmentDescription[i].MandateOutput;
            MandateOutput memory output = MandateOutputs[i];

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
        InputSettler7683LIFIHarness(inputsettler7683).validateFills(address(this), orderId, MandateOutputs);
    }

    // --- Fee tests --- //

    function test_invalid_governance_fee() public {
        vm.prank(owner);
        InputSettler7683LIFIHarness(inputsettler7683).setGovernanceFee(MAX_GOVERNANCE_FEE);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        InputSettler7683LIFIHarness(inputsettler7683).setGovernanceFee(MAX_GOVERNANCE_FEE + 1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        InputSettler7683LIFIHarness(inputsettler7683).setGovernanceFee(MAX_GOVERNANCE_FEE + 123123123);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeTooHigh()"));
        InputSettler7683LIFIHarness(inputsettler7683).setGovernanceFee(type(uint64).max);
    }

    function test_governance_fee_change_not_ready(uint64 fee, uint256 timeDelay) public {
        vm.assume(fee <= MAX_GOVERNANCE_FEE);
        vm.assume(timeDelay < uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);

        vm.prank(owner);
        vm.expectEmit();
        emit NextGovernanceFee(fee, uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY);
        InputSettler7683LIFIHarness(inputsettler7683).setGovernanceFee(fee);

        vm.warp(timeDelay);
        vm.expectRevert(abi.encodeWithSignature("GovernanceFeeChangeNotReady()"));
        InputSettler7683LIFIHarness(inputsettler7683).applyGovernanceFee();

        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);

        assertEq(InputSettler7683LIFIHarness(inputsettler7683).governanceFee(), 0);

        vm.expectEmit();
        emit GovernanceFeeChanged(0, fee);
        InputSettler7683LIFIHarness(inputsettler7683).applyGovernanceFee();

        assertEq(InputSettler7683LIFIHarness(inputsettler7683).governanceFee(), fee);
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
        InputSettler7683LIFIHarness(inputsettler7683).setGovernanceFee(fee);
        vm.warp(uint32(block.timestamp) + GOVERNANCE_FEE_CHANGE_DELAY + 1);
        InputSettler7683LIFIHarness(inputsettler7683).applyGovernanceFee();

        uint256 amount = 1e18 / 10;
        address localOracle = address(alwaysYesOracle);

        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = MandateOutput({
            settler: bytes32(uint256(uint160(address(outputSettlerCoin)))),
            oracle: bytes32(uint256(uint160(localOracle))),
            chainId: block.chainid,
            token: bytes32(uint256(uint160(address(anotherToken)))),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            call: hex"",
            context: hex""
        });
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(uint160(address(token))), amount];

        MandateERC7683 memory mandate =
            MandateERC7683({ expiry: type(uint32).max, localOracle: localOracle, inputs: inputs, outputs: outputs });

        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: type(uint32).max,
            orderDataType: bytes32(0),
            orderData: abi.encode(mandate)
        });

        // Deposit into the escrow
        vm.prank(swapper);
        token.approve(inputsettler7683, amount);
        vm.prank(swapper);
        InputSettler7683LIFIHarness(inputsettler7683).open(order);

        uint32[] memory timestamps = new uint32[](1);
        timestamps[0] = uint32(block.timestamp);

        // Generate the StandardOrder so we can make the finalise call
        StandardOrder memory compactOrder = StandardOrder({
            user: swapper,
            nonce: 0,
            originChainId: block.chainid,
            expires: mandate.expiry,
            fillDeadline: order.fillDeadline,
            localOracle: mandate.localOracle,
            inputs: mandate.inputs,
            outputs: mandate.outputs
        });

        bytes32 orderId = InputSettler7683LIFIHarness(inputsettler7683).orderIdentifier(compactOrder);
        bytes memory payload = MandateOutputEncodingLib.encodeFillDescriptionMemory(
            bytes32(uint256(uint160((solver)))), orderId, uint32(block.timestamp), outputs[0]
        );
        bytes32 payloadHash = keccak256(payload);

        vm.expectCall(
            address(alwaysYesOracle),
            abi.encodeWithSignature(
                "efficientRequireProven(bytes)",
                abi.encodePacked(
                    mandate.outputs[0].chainId, mandate.outputs[0].oracle, mandate.outputs[0].settler, payloadHash
                )
            )
        );

        vm.prank(solver);
        InputSettler7683LIFIHarness(inputsettler7683).finaliseSelf(
            compactOrder, timestamps, bytes32(uint256(uint160((solver))))
        );
        vm.snapshotGasLastCall("inputSettler", "7683FinaliseSelfWithFee");

        uint256 govFeeAmount = (amount * fee) / 10 ** 18;
        uint256 amountPostFee = amount - govFeeAmount;

        assertEq(token.balanceOf(solver), amountPostFee);
        assertEq(token.balanceOf(InputSettler7683LIFIHarness(inputsettler7683).owner()), govFeeAmount);
    }
}
