// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { TheCompact } from "the-compact/src/TheCompact.sol";
import { AlwaysOKAllocator } from "the-compact/src/test/AlwaysOKAllocator.sol";

import { CoinFiller } from "OIF/src/fillers/coin/CoinFiller.sol";
import { WormholeOracle } from "OIF/src/oracles/wormhole/WormholeOracle.sol";
import { AlwaysYesOracle } from "OIF/test/mocks/AlwaysYesOracle.sol";

import { multichain } from "./multichain.s.sol";

import { LIFISettlerCompactWithDeposit } from "../src/settlers/compact/LIFISettlerCompactWithDeposit.sol";

contract deployWormhole is multichain {
    error NotExpectedAddress(string name, address expected, address actual);
    address public constant COMPACT = address(0xE7d08C4D2a8AB8512b6a920bA8E4F4F11f78d376);

    string private constant WORMHOLE_CONFIG = "/script/wormhole.json";

    function run(string[] calldata chains) public returns (WormholeOracle oracle) {
        return run(chains, getSender());
    }

    function run(string[] calldata chains, address initialOwner) iter_chains(chains) broadcast public returns (WormholeOracle oracle) {
        string memory activeChain = getChain();
        // Load wormhole config.
        string memory pathRoot = vm.projectRoot();
        string memory pathToWormholeConfig = string(abi.encodePacked(pathRoot, WORMHOLE_CONFIG));
        string memory wormholeConfig = vm.readFile(pathToWormholeConfig);

        address wormholeImplementation = vm.parseJsonAddress(wormholeConfig, string.concat(".implementation.", activeChain, ".wormhole"));
        
        // Deploy the Wormhole Oracle.
        oracle = deployWormholeOracle(initialOwner, wormholeImplementation);
        vm.writeJson(vm.toString(address(oracle)), pathToWormholeConfig, string.concat(".implementation.", activeChain, ".oracle"));

        bytes memory chainIdData = vm.parseJson(wormholeConfig, ".chainids");
        uint256[][] memory chainIdArray = abi.decode(chainIdData, (uint256[][]));
        for (uint256 i = 0; i < chainIdArray.length; i++) {
            assert(chainIdArray[i].length == 2);
            uint256 chainId = chainIdArray[i][0];
            uint16 messagingProtocolChainIdentifier = uint16(chainIdArray[i][1]);
            // Set the chain map for the Wormhole Oracle.
            setWormholeConfig(oracle, messagingProtocolChainIdentifier, chainId);
        }
    }

    function deployWormholeOracle(address initialOwner, address wormholeImplementation) internal returns (WormholeOracle oracle) {
        address expectedAddress = getExpectedCreate2Address(
            0, // salt
            type(WormholeOracle).creationCode,
            abi.encode(initialOwner, wormholeImplementation)
        );
        bool isOracleDeployed = address(expectedAddress).code.length != 0;

        if (!isOracleDeployed) {
            return new WormholeOracle{salt: 0}(initialOwner, wormholeImplementation);
        }
        return WormholeOracle(expectedAddress);
    }

    function setWormholeConfig(WormholeOracle oracle, uint16 messagingProtocolChainIdentifier, uint256 chainId) internal {
        // Check if map has already been set.
        uint256 storedBlockChainid = oracle.getChainIdentifierToBlockChainId(messagingProtocolChainIdentifier);
        uint256 storedChainIdentifier = oracle.getBlockChainIdToChainIdentifier(chainId);
        if (storedBlockChainid != 0 || storedChainIdentifier != 0) {
            // Check whether the maps has been set to the expected values:
            if (storedBlockChainid == chainId && storedChainIdentifier == messagingProtocolChainIdentifier) {
                // Then skip.
                return;
            }
            revert WormholeOracle.AlreadySet();
        }
        // Set the map.
        oracle.setChainMap(messagingProtocolChainIdentifier, chainId);
    }
}

