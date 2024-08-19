// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { CrossChainDutchOrderType, DutchOrderData } from "../../src/libs/ordertypes/CrossChainDutchOrderType.sol";

import { TestPermit } from "./TestPermit.t.sol";

contract TestPermitDutchOrder is TestPermit {
    function setUp() public { }

    function test_dutch_type_hash() public {
        bytes32 expectedHash = keccak256(
            abi.encodePacked(
                "PermitBatchWitnessTransferFrom"
                "(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,CrossChainOrder witness)"
                "CatalystDutchOrderData(" "bytes32 verificationContext," "address verificationContract,"
                "uint32 proofDeadline,uint32 challengeDeadline,address collateralToken,uint256 fillerCollateralAmount,"
                "uint256 challengerCollateralAmount,address localOracle,bytes32[] remoteOracles,"
                "uint32 slopeStartingTime,int256[] inputSlopes,int256[] outputSlopes,Input[] inputs,Output[] outputs)"
                "CrossChainOrder(address settlementContract,address swapper,uint256 nonce,"
                "uint32 originChainId,uint32 initiateDeadline,uint32 fillDeadline,CatalystDutchOrderData orderData)"
                "Input(address token,uint256 amount)"
                "Output(bytes32 token,uint256 amount,bytes32 recipient,uint32 chainId)"
                "TokenPermissions(address token,uint256 amount)"
            )
        );

        bytes32 actualHash = FULL_ORDER_PERMIT2_TYPE_HASH;
        assertEq(expectedHash, actualHash);
    }

    function _orderType() internal virtual override returns (bytes memory) {
        return CrossChainDutchOrderType.getOrderType();
    }
}
