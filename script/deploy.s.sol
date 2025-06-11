// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { TheCompact } from "the-compact/src/TheCompact.sol";
import { IdLib } from "the-compact/src/lib/IdLib.sol";
import { AlwaysOKAllocator } from "the-compact/src/test/AlwaysOKAllocator.sol";

import { WormholeOracle } from "OIF/src/oracles/wormhole/WormholeOracle.sol";
import { OutputSettlerCoin } from "OIF/src/output/coin/OutputSettlerCoin.sol";
import { AlwaysYesOracle } from "OIF/test/mocks/AlwaysYesOracle.sol";

import { multichain } from "./multichain.s.sol";

import { InputSettlerCompactLIFIWithDeposit } from "../src/input/compact/InputSettlerCompactLIFIWithDeposit.sol";

contract deploy is multichain {
    error NotExpectedAddress(string name, address expected, address actual);

    address public constant COMPACT = address(0x70EEFf73E540C8F68477510F096c0d903D31594a);
    uint256 private constant _ALLOCATOR_BY_ALLOCATOR_ID_SLOT_SEED = 0x000044036fc77deaed2300000000000000000000000;

    function run(
        string[] calldata chains
    ) public returns (InputSettlerCompactLIFIWithDeposit settler) {
        return run(chains, getSender());
    }

    function run(
        string[] calldata chains,
        address initialOwner
    ) public returns (InputSettlerCompactLIFIWithDeposit settler) {
        address expectedSettlerAddress = getExpectedCreate2Address(
            0, // salt
            type(InputSettlerCompactLIFIWithDeposit).creationCode,
            abi.encode(COMPACT, initialOwner)
        );
        return run(chains, initialOwner, expectedSettlerAddress);
    }

    function run(
        string[] calldata chains,
        address initialOwner,
        address expectedSettlerAddress
    ) public iter_chains(chains) broadcast returns (InputSettlerCompactLIFIWithDeposit settler) {
        deployCompact();
        settler = deploySettler(initialOwner, expectedSettlerAddress);

        deployOutputSettlerCoin();
        deployAlwaysOkAllocaor();
        deployAlwaysYesOracle();
    }

    function deploySettler(
        address initialOwner,
        address expectedSettlerAddress
    ) internal returns (InputSettlerCompactLIFIWithDeposit settler) {
        bool isSettlerDeployed = address(expectedSettlerAddress).code.length != 0;

        if (!isSettlerDeployed) {
            settler = new InputSettlerCompactLIFIWithDeposit{ salt: 0 }(COMPACT, initialOwner);

            if (expectedSettlerAddress != address(settler)) {
                revert NotExpectedAddress("settler", expectedSettlerAddress, address(settler));
            }
            return settler;
        }
        return InputSettlerCompactLIFIWithDeposit(expectedSettlerAddress);
    }

    function deployCompact() internal {
        bool isCompactDeployed = COMPACT.code.length != 0;

        if (!isCompactDeployed) {
            address compact = address(new TheCompact{ salt: 0 }());

            if (COMPACT != compact) revert NotExpectedAddress("compact", COMPACT, compact);
        }
    }

    function deployOutputSettlerCoin() internal returns (OutputSettlerCoin filler) {
        address expectedAddress = getExpectedCreate2Address(
            0, // salt
            type(OutputSettlerCoin).creationCode,
            hex""
        );
        bool isFillerDeployed = address(expectedAddress).code.length != 0;

        if (!isFillerDeployed) return filler = new OutputSettlerCoin{ salt: 0 }();
        return OutputSettlerCoin(expectedAddress);
    }

    function deployAlwaysOkAllocaor() internal returns (AlwaysOKAllocator allocator, uint96 allocatorId) {
        address expectedAddress = getExpectedCreate2Address(
            0, // salt
            type(AlwaysOKAllocator).creationCode,
            hex""
        );
        bool isAllocatorDeployed = address(expectedAddress).code.length != 0;

        if (!isAllocatorDeployed) allocator = new AlwaysOKAllocator{ salt: 0 }();
        else allocator = AlwaysOKAllocator(expectedAddress);

        allocatorId = IdLib.toAllocatorId(address(allocator));

        bytes32 storageSlotKey;
        assembly {
            storageSlotKey := or(_ALLOCATOR_BY_ALLOCATOR_ID_SLOT_SEED, allocatorId)
        }

        bytes32 storageSlotValue = vm.load(COMPACT, storageSlotKey);
        if (storageSlotValue == bytes32(0)) {
            uint96 registeredAllocatorId = TheCompact(COMPACT).__registerAllocator(address(allocator), "");
            assert(registeredAllocatorId == allocatorId);
        }
    }

    function deployAlwaysYesOracle() internal returns (AlwaysYesOracle oracle) {
        address expectedAddress = getExpectedCreate2Address(
            0, // salt
            type(AlwaysYesOracle).creationCode,
            hex""
        );
        bool isOracleDeployed = address(expectedAddress).code.length != 0;

        if (!isOracleDeployed) return oracle = new AlwaysYesOracle{ salt: 0 }();
        return AlwaysYesOracle(expectedAddress);
    }
}
