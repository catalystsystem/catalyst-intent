// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;


import "forge-std/Test.sol";

import { DeployCompact } from "./DeployCompact.t.sol";

import { CatalystCompactSettler } from "../src/reactors/settler/CatalystCompactSettler.sol";
import { CoinFiller } from "../src/reactors/filler/CoinFiller.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { AlwaysYesOracle } from "./mocks/AlwaysYesOracle.sol";

import { InputDescription, OutputDescription, CatalystOrderData, CatalystOrderType } from "../src/reactors/CatalystOrderType.sol";
import { GaslessCrossChainOrder } from "../src/interfaces/IERC7683.sol";


contract TestCatalyst is DeployCompact {
    CatalystCompactSettler catalystCompactSettler;
    CoinFiller coinFiller;
    address alwaysYesOracle;

    uint256 swapperPrivateKey;
    address swapper;

    MockERC20 token;
    MockERC20 anotherToken;

    function orderHash(
        GaslessCrossChainOrder memory order,
        CatalystOrderData memory orderData
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CatalystOrderType.GASSLESS_CROSS_CHAIN_ORDER_TYPE_HASH,
                order.originSettler,
                order.user,
                order.nonce,
                order.originChainId,
                order.openDeadline,
                order.fillDeadline,
                order.orderDataType,
                CatalystOrderType.hashOrderDataM(orderData)
            )
        );
    }

    function setUp() public override virtual {
        super.setUp();

        catalystCompactSettler = new CatalystCompactSettler(address(theCompact));
        coinFiller = new CoinFiller();
        alwaysYesOracle = address(new AlwaysYesOracle());

        token = new MockERC20("Mock ERC20", "MOCK", 18);
        anotherToken = new MockERC20("Mock2 ERC20", "MOCK2", 18);

        (swapper, swapperPrivateKey) = makeAddrAndKey("swapper");

        vm.deal(swapper, 1e18);
        token.mint(swapper, 1e18);
        
        vm.prank(swapper);
        token.approve(address(theCompact), type(uint256).max);
    }

    function test_deposit_compact() external {
        vm.prank(swapper);
        theCompact.deposit(address(token), alwaysOKAllocator, 1e18/10);
    }

    function test_deposit_and_claim() external {
        vm.prank(swapper);
        uint256 amount = 1e18/10;
        uint256 tokenId = theCompact.deposit(address(token), alwaysOKAllocator, amount);

        InputDescription[] memory inputs = new InputDescription[](1);
        inputs[0] = InputDescription({
            tokenId: tokenId,
            amount: amount
        });
        OutputDescription[] memory outputs = new OutputDescription[](1);
        outputs[0] = OutputDescription({
            remoteOracle: bytes32(uint256(uint160(alwaysYesOracle))),
            chainId: block.chainid,
            token: bytes32(tokenId),
            amount: amount,
            recipient: bytes32(uint256(uint160(swapper))),
            remoteCall: hex"",
            fulfillmentContext: hex""
        });
        CatalystOrderData memory orderData = CatalystOrderData({
            localOracle: alwaysYesOracle,
            collateralToken: address(0),
            collateralAmount: uint256(0),
            proofDeadline: type(uint32).max,
            challengeDeadline: type(uint32).max,
            inputs: inputs,
            outputs: outputs
        });
        GaslessCrossChainOrder memory order = GaslessCrossChainOrder({
            originSettler: address(catalystCompactSettler),
            user: address(swapper),
            nonce: 0,
            originChainId: block.chainid,
            openDeadline: type(uint32).max,
            fillDeadline: type(uint32).max,
            orderDataType: CatalystOrderType.CATALYST_ORDER_DATA_TYPE_HASH,
            orderData: abi.encode(orderData)
        });

        // Make Compact
        bytes32 typeHash = CatalystOrderType.BATCH_COMPACT_TYPE_HASH;
        uint256[2][] memory idsAndAmounts = new uint256[2][](1);
        idsAndAmounts[0] = [tokenId, amount];

        bytes memory sponsorSig = getCompactBatchWitnessSignature(
            swapperPrivateKey,
            typeHash,
            address(catalystCompactSettler),
            swapper,
            0,
            type(uint32).max,
            idsAndAmounts,
            orderHash(order, orderData)
        );
        bytes memory allocatorSig = hex"";

        bytes memory signature = abi.encode(sponsorSig, allocatorSig);
        
        address solver;
        uint40[] memory timestamps = new uint40[](1);
        bytes memory originFllerData = abi.encode(solver, timestamps);

        catalystCompactSettler.openFor(order, signature, originFllerData);
    }
}