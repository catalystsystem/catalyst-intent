// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DeployDutchOrderReactor } from "../../script/Reactor/DeployDutchOrderReactor.s.sol";

import { CrossChainOrder } from "../../src/interfaces/ISettlementContract.sol";
import {
    CatalystDutchOrderData, CrossChainDutchOrderType
} from "../../src/libs/ordertypes/CrossChainDutchOrderType.sol";
import { CrossChainOrderType } from "../../src/libs/ordertypes/CrossChainOrderType.sol";
import { CrossChainBuilder } from "../utils/CrossChainBuilder.t.sol";

import { OrderKey } from "../../src/interfaces/Structs.sol";
import { Permit2Lib } from "../../src/libs/Permit2Lib.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { OrderDataBuilder } from "../utils/OrderDataBuilder.t.sol";
import { OrderKeyInfo } from "../utils/OrderKeyInfo.t.sol";
import { SigTransfer } from "../utils/SigTransfer.t.sol";
import { TestPermit } from "./TestPermit.t.sol";

import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";

interface Permit2DomainSeparator {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract TestPermitDutchOrder is TestPermit, DeployDutchOrderReactor {
    bytes constant EXPECTED_PERMIT_BATCH_TYPE = abi.encodePacked(
        "PermitBatchWitnessTransferFrom"
        "(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,CrossChainOrder witness)"
        "CatalystDutchOrderData(bytes32 verificationContext,address verificationContract,"
        "uint32 proofDeadline,uint32 challengeDeadline,address collateralToken,uint256 fillerCollateralAmount,"
        "uint256 challengerCollateralAmount,address localOracle,"
        "uint32 slopeStartingTime,int256[] inputSlopes,int256[] outputSlopes,Input[] inputs,OutputDescription[] outputs)"
        "CrossChainOrder(address settlementContract,address swapper,uint256 nonce,"
        "uint32 originChainId,uint32 initiateDeadline,uint32 fillDeadline,CatalystDutchOrderData orderData)"
        "Input(address token,uint256 amount)" "OutputDescription(bytes32 remoteOracle,bytes32 token,uint256 amount,"
        "bytes32 recipient,uint32 chainId,bytes remoteCall)" "TokenPermissions(address token,uint256 amount)"
    );

    function setUp() public {
        address reactorDeployer = vm.addr(deployerKey);
        reactor = deploy(reactorDeployer);
        DOMAIN_SEPARATOR = Permit2DomainSeparator(permit2).DOMAIN_SEPARATOR();
    }

    function test_dutch_type_hash() public {
        bytes32 expectedHash = keccak256(EXPECTED_PERMIT_BATCH_TYPE);
        bytes32 actualHash = _getFullPermitTypeHash();
        assertEq(expectedHash, actualHash);
    }

    function test_cross_order_with_permit(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 challengerCollateralAmount,
        uint256 fillerCollateralAmount,
        uint32 initiateDeadline
    ) public {
        vm.assume(initiateDeadline > 0);
        CatalystDutchOrderData memory dutchOrderData = OrderDataBuilder.getDutchOrder(
            tokenToSwapInput,
            tokenToSwapOutput,
            inputAmount,
            outputAmount,
            SWAPPER,
            collateralToken,
            challengerCollateralAmount,
            fillerCollateralAmount,
            1,
            2,
            localVMOracle,
            remoteVMOracle
        );

        CrossChainOrder memory order = CrossChainBuilder.getCrossChainOrder(
            dutchOrderData, address(reactor), SWAPPER, 0, uint32(block.chainid), initiateDeadline, 1
        );
        OrderKey memory orderKey = OrderKeyInfo.getOrderKey(order, reactor);

        bytes memory expectedInputTypeStub = abi.encodePacked("Input(", "address token,", "uint256 amount", ")");
        bytes memory expectedOutputTypeStub = abi.encodePacked(
            "OutputDescription(",
            "bytes32 remoteOracle,",
            "bytes32 token,",
            "uint256 amount,",
            "bytes32 recipient,",
            "uint32 chainId,",
            "bytes remoteCall",
            ")"
        );
        bytes32 expectedHashedInput =
            keccak256(abi.encode(keccak256(expectedInputTypeStub), tokenToSwapInput, inputAmount));

        bytes32 expectedHashedInputArray = keccak256(abi.encode(expectedHashedInput));

        bytes32 expectedRecipientBytes = bytes32(uint256(uint160(SWAPPER)));
        bytes32 expectedOutputTokenBytes = bytes32(uint256(uint160(tokenToSwapOutput)));

        bytes32 expectedHashedOutput = keccak256(
            abi.encode(
                keccak256(expectedOutputTypeStub),
                dutchOrderData.outputs[0].remoteOracle,
                expectedOutputTokenBytes,
                outputAmount,
                expectedRecipientBytes,
                uint32(block.chainid),
                keccak256(dutchOrderData.outputs[0].remoteCall)
            )
        );

        bytes32 expectedHashedOutputArray = keccak256(abi.encode(expectedHashedOutput));

        bytes memory expectedDutchOrderDataType = abi.encodePacked(
            "CatalystDutchOrderData(",
            "bytes32 verificationContext,",
            "address verificationContract,",
            "uint32 proofDeadline,",
            "uint32 challengeDeadline,",
            "address collateralToken,",
            "uint256 fillerCollateralAmount,",
            "uint256 challengerCollateralAmount,",
            "address localOracle,",
            "uint32 slopeStartingTime,",
            "int256[] inputSlopes,",
            "int256[] outputSlopes,",
            "Input[] inputs,",
            "OutputDescription[] outputs",
            ")",
            expectedInputTypeStub,
            expectedOutputTypeStub
        );
        bytes memory expectedDutchPlainDataEncoded = abi.encode(
            keccak256(expectedDutchOrderDataType),
            dutchOrderData.verificationContext,
            dutchOrderData.verificationContract,
            dutchOrderData.proofDeadline,
            dutchOrderData.challengeDeadline,
            dutchOrderData.collateralToken,
            dutchOrderData.fillerCollateralAmount,
            dutchOrderData.challengerCollateralAmount,
            dutchOrderData.localOracle,
            dutchOrderData.slopeStartingTime
        );
        bytes memory expectedDutchArrayDataEncoded = abi.encode(
            keccak256(abi.encodePacked(dutchOrderData.inputSlopes)),
            keccak256(abi.encodePacked(dutchOrderData.outputSlopes)),
            expectedHashedInputArray,
            expectedHashedOutputArray
        );

        bytes32 expectedHashedDutchOrderData =
            keccak256(bytes.concat(expectedDutchPlainDataEncoded, expectedDutchArrayDataEncoded));

        bytes memory expectedOrderType = abi.encodePacked(
            "CrossChainOrder(",
            "address settlementContract,",
            "address swapper,",
            "uint256 nonce,",
            "uint32 originChainId,",
            "uint32 initiateDeadline,",
            "uint32 fillDeadline,",
            "CatalystDutchOrderData orderData",
            ")",
            expectedDutchOrderDataType
        );

        bytes32 expectedHashedCrossOrderType = keccak256(
            abi.encode(
                keccak256(expectedOrderType),
                order.settlementContract,
                order.swapper,
                order.nonce,
                order.originChainId,
                order.initiateDeadline,
                order.fillDeadline,
                expectedHashedDutchOrderData
            )
        );

        bytes32 actualHashedCrossOrderType = this._getWitnessHash(order, dutchOrderData);
        assertEq(expectedHashedCrossOrderType, actualHashedCrossOrderType);
        ISignatureTransfer.TokenPermissions[] memory expectedPermitted = new ISignatureTransfer.TokenPermissions[](1);
        expectedPermitted[0] = ISignatureTransfer.TokenPermissions({ token: tokenToSwapInput, amount: inputAmount });

        ISignatureTransfer.SignatureTransferDetails[] memory expectedTransferDetails =
            new ISignatureTransfer.SignatureTransferDetails[](1);

        expectedTransferDetails[0] =
            ISignatureTransfer.SignatureTransferDetails({ to: address(reactor), requestedAmount: inputAmount });

        ISignatureTransfer.PermitBatchTransferFrom memory expectedPermitBatch = ISignatureTransfer
            .PermitBatchTransferFrom({ permitted: expectedPermitted, nonce: 0, deadline: uint32(order.initiateDeadline) });

        bytes32 expectedHashedTokenPermission =
            keccak256(abi.encodePacked(keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, expectedPermitted[0]))));

        bytes32 expectedSigHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        keccak256(EXPECTED_PERMIT_BATCH_TYPE),
                        expectedHashedTokenPermission,
                        address(reactor),
                        expectedPermitBatch.nonce,
                        expectedPermitBatch.deadline,
                        expectedHashedCrossOrderType
                    )
                )
            )
        );
        (
            ISignatureTransfer.PermitBatchTransferFrom memory actualPermitBatch,
            ISignatureTransfer.SignatureTransferDetails[] memory actualTransferDetails
        ) = Permit2Lib.toPermit(
            orderKey, Permit2Lib.inputsToPermittedAmounts(orderKey.inputs), address(reactor), order.initiateDeadline
        );

        bytes32[] memory actualTokenPermissions = new bytes32[](actualPermitBatch.permitted.length);
        for (uint256 i = 0; i < actualPermitBatch.permitted.length; ++i) {
            actualTokenPermissions[i] =
                keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, actualPermitBatch.permitted[i]));
        }

        bytes32 actualSigHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        _getFullPermitTypeHash(),
                        keccak256(abi.encodePacked(actualTokenPermissions)),
                        address(reactor),
                        actualPermitBatch.nonce,
                        actualPermitBatch.deadline,
                        actualHashedCrossOrderType
                    )
                )
            )
        );

        assertEq(expectedSigHash, actualSigHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SWAPPER_PRIVATE_KEY, actualSigHash);
        bytes memory sig = bytes.concat(r, s, bytes1(v));

        vm.prank(SWAPPER);
        MockERC20(tokenToSwapInput).approve(permit2, type(uint256).max);
        MockERC20(tokenToSwapInput).mint(SWAPPER, inputAmount);
        vm.prank(address(reactor));
        ISignatureTransfer(permit2).permitWitnessTransferFrom(
            actualPermitBatch,
            actualTransferDetails,
            SWAPPER,
            actualHashedCrossOrderType,
            CrossChainDutchOrderType.PERMIT2_DUTCH_ORDER_WITNESS_STRING_TYPE,
            sig
        );

        assertEq(MockERC20(tokenToSwapInput).balanceOf(address(reactor)), inputAmount);
        assertEq(MockERC20(tokenToSwapInput).balanceOf(SWAPPER), 0);
    }

    function _getFullPermitTypeHash() internal pure override returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                SigTransfer.PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB,
                CrossChainDutchOrderType.PERMIT2_DUTCH_ORDER_WITNESS_STRING_TYPE
            )
        );
    }

    function _getWitnessHash(
        CrossChainOrder calldata order,
        CatalystDutchOrderData memory dutchOrderData
    ) public pure returns (bytes32) {
        return CrossChainDutchOrderType.crossOrderHash(order, dutchOrderData);
    }
}
