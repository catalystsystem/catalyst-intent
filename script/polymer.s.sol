// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import { PolymerOracle } from "OIF/src/integrations/oracles/polymer/PolymerOracle.sol";
import { PolymerOracleMapped } from "OIF/src/integrations/oracles/polymer/PolymerOracleMapped.sol";
import { ChainMap } from "OIF/src/oracles/ChainMap.sol";

import { multichain } from "./multichain.s.sol";

import {console} from "forge-std/console.sol";

contract deployPolymer is multichain {
    error NotExpectedAddress(string name, address expected, address actual);

    string private constant POLYMER_CONFIG = "/script/polymer.json";

    mapping(address => bytes32) polymerSalts;

    constructor() {
        polymerSalts[0x03Fb5bFA4EB2Cba072A477A372bB87880A60fC96] =
            0x00000000000000000000000000000000000000003f5a1d9c8d66f846fc58000c;
        polymerSalts[0x95ccEAE71605c5d97A0AC0EA13013b058729d075] =
            0x00000000000000000000000000000000000000004f09241f65a03e2a3e020030;
    }

    function run(
        string[] calldata chains
    ) public returns (address oracle) {
        return run(chains, getSender());
    }

    function run(
        string[] calldata chains,
        address initialOwner
    ) public iter_chains(chains) broadcast returns (address oracle) {
        string memory activeChain = getChain();
        // Load polymer config.
        string memory pathRoot = vm.projectRoot();
        string memory pathToPolymerConfig = string(abi.encodePacked(pathRoot, POLYMER_CONFIG));
        string memory polymerConfig = vm.readFile(pathToPolymerConfig);

        address polymerImplementation =
            vm.parseJsonAddress(polymerConfig, string.concat(".implementation.", activeChain, ".polymer"));

        // Deploy the Polymer Oracle.
        oracle = initialOwner == address(0)
            ? deployNonMappedPolymerOracle(polymerImplementation)
            : deployPolymerOracle(initialOwner, polymerImplementation);
        vm.writeJson(
            vm.toString(address(oracle)), pathToPolymerConfig, string.concat(".implementation.", activeChain, ".oracle")
        );

        if (initialOwner != address(0)) {
            bytes memory chainIdData = vm.parseJson(polymerConfig, ".chainids");
            uint256[][] memory chainIdArray = abi.decode(chainIdData, (uint256[][]));
            for (uint256 i = 0; i < chainIdArray.length; i++) {
                assert(chainIdArray[i].length == 2);
                uint256 chainId = chainIdArray[i][0];
                uint32 messagingProtocolChainIdentifier = uint32(chainIdArray[i][1]);
                // Set the chain map for the Polymer Oracle.
                setPolymerConfig(PolymerOracleMapped(oracle), messagingProtocolChainIdentifier, chainId);
            }
        }
    }

    function deployNonMappedPolymerOracle(
        address polymerImplementation
    ) internal returns (address oracle) {
        address expectedAddress = getExpectedCreate2Address(
            polymerSalts[polymerImplementation], // salt
            type(PolymerOracle).creationCode,
            abi.encode(polymerImplementation)
        );
        bool isOracleDeployed = address(expectedAddress).code.length != 0;

        if (!isOracleDeployed) {
            return address(new PolymerOracle{ salt: polymerSalts[polymerImplementation] }(polymerImplementation));
        }
        return expectedAddress;
    }

    function deployPolymerOracle(
        address initialOwner,
        address polymerImplementation
    ) internal returns (address oracle) {
        address expectedAddress = getExpectedCreate2Address(
            0, // salt
            type(PolymerOracleMapped).creationCode,
            abi.encode(initialOwner, polymerImplementation)
        );
        bool isOracleDeployed = address(expectedAddress).code.length != 0;

        if (!isOracleDeployed) return address(new PolymerOracleMapped{ salt: 0 }(initialOwner, polymerImplementation));
        return expectedAddress;
    }

    function setPolymerConfig(
        PolymerOracleMapped oracle,
        uint32 messagingProtocolChainIdentifier,
        uint256 chainId
    ) internal {
        // Check if map has already been set.
        uint256 storedBlockChainid = oracle.chainIdMap(messagingProtocolChainIdentifier);
        uint256 storedChainIdentifier = oracle.reverseChainIdMap(chainId);
        if (storedBlockChainid != 0 || storedChainIdentifier != 0) {
            // Check whether the maps has been set to the expected values:
            if (storedBlockChainid == chainId && storedChainIdentifier == messagingProtocolChainIdentifier) {
                // Then skip.
                return;
            }
            revert ChainMap.AlreadySet();
        }
        // Set the map.
        oracle.setChainMap(messagingProtocolChainIdentifier, chainId);
    }
}
