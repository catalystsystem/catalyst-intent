// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { MockERC20 } from "../../test/mocks/MockERC20.sol";
import { MockOracle } from "../../test/mocks/MockOracle.sol";

import { IncentivizedMockEscrow } from "GeneralisedIncentives/apps/mock/IncentivizedMockEscrow.sol";
import { IIncentivizedMessageEscrow } from "GeneralisedIncentives/interfaces/IIncentivizedMessageEscrow.sol";

import { Script } from "forge-std/Script.sol";

import { DeployPermit2 } from "permit2/test/utils/DeployPermit2.sol";

interface Permit2DomainSeparator {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract ReactorHelperConfig is Script, DeployPermit2 {
    NetworkConfig public currentConfig;

    // We can also add the domain separator here.
    struct NetworkConfig {
        //TODO: Possible to make it array in the future;
        address tokenToSwapInput;
        address tokenToSwapOutput;
        address collateralToken;
        address localVMOracle;
        address remoteVMOracle;
        address escrow;
        address permit2;
        uint256 deployerKey;
    }

    // Default ANVIL KEY
    uint256 public ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11_155_111) {
            currentConfig = _getSepoliaConfig();
        } else {
            currentConfig = _getAnvilConfig();
        }
    }

    function _getSepoliaConfig() internal view returns (NetworkConfig memory sepoliaConfig) {
        sepoliaConfig = NetworkConfig({
            tokenToSwapInput: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, //WETH address on sepolia
            tokenToSwapOutput: 0x61EDCDf5bb737ADffE5043706e7C5bb1f1a56eEA, //BETH address on sepolia
            //TODO: Change with a valid address
            collateralToken: address(0),
            // TODO: change with the deployed oracle addresses and their escrow when deployed to testnets
            localVMOracle: address(0),
            remoteVMOracle: address(0),
            escrow: address(0),
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3, //Permit2 multichain address
            deployerKey: vm.envUint("PK")
        });
    }

    function _getAnvilConfig() internal returns (NetworkConfig memory anvilConfig) {
        if (currentConfig.tokenToSwapInput != address(0)) return currentConfig;
        vm.startBroadcast();
        MockERC20 input = new MockERC20("TestTokenInput", "TTI", 18);
        MockERC20 output = new MockERC20("TestTokenOutput", "ERC", 18);
        MockERC20 collateral = new MockERC20("TestCollateralToken", "TTC", 18);

        IIncentivizedMessageEscrow escrow =
            new IncentivizedMockEscrow(address(uint160(0xdead)), bytes32(block.chainid), address(5), 0, 0);

        MockOracle localOracle = new MockOracle(address(escrow), uint32(block.chainid));
        MockOracle remoteOracle = new MockOracle(address(escrow), uint32(block.chainid));
        address permit2 = deployPermit2();
        vm.stopBroadcast();

        anvilConfig = NetworkConfig({
            tokenToSwapInput: address(input),
            tokenToSwapOutput: address(output),
            collateralToken: address(collateral),
            localVMOracle: address(localOracle),
            remoteVMOracle: address(remoteOracle),
            escrow: address(escrow),
            permit2: permit2,
            deployerKey: ANVIL_PRIVATE_KEY
        });
    }
}
