// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import {TheCompact} from "the-compact/src/TheCompact.sol";
import {IdLib} from "the-compact/src/lib/IdLib.sol";
import {AlwaysOKAllocator} from "the-compact/src/test/AlwaysOKAllocator.sol";

import {OutputSettlerSimple} from "OIF/src/output/simple/OutputSettlerSimple.sol";
import {AlwaysYesOracle} from "OIF/test/mocks/AlwaysYesOracle.sol";

import {multichain} from "./multichain.s.sol";

import {InputSettlerCompactLIFI} from "../src/input/compact/InputSettlerCompactLIFI.sol";

contract deploy is multichain {
    error NotExpectedAddress(string name, address expected, address actual);

    address public constant COMPACT =
        address(0x0000000038568013727833b4Ad37B53bb1b6f09d);
    uint256 private constant _ALLOCATOR_BY_ALLOCATOR_ID_SLOT_SEED =
        0x000044036fc77deaed2300000000000000000000000;

    bytes32 inputSettlerSalt =
        0x00000000000000000000000000000000000000000b1014d05f5714cab52d000c;
    bytes32 outputSettlerSalt =
        0x00000000000000000000000000000000000000002314fd828687df37e06200b0;

    function run(
        string[] calldata chains
    ) public returns (InputSettlerCompactLIFI settler) {
        return run(chains, getSender());
    }

    function run(
        string[] calldata chains,
        address initialOwner
    ) public returns (InputSettlerCompactLIFI settler) {
        address expectedSettlerAddress = getExpectedCreate2Address(
            inputSettlerSalt, // salt
            type(InputSettlerCompactLIFI).creationCode,
            abi.encode(COMPACT, initialOwner)
        );
        return run(chains, initialOwner, expectedSettlerAddress);
    }

    function run(
        string[] calldata chains,
        address initialOwner,
        address expectedSettlerAddress
    )
        public
        iter_chains(chains)
        broadcast
        returns (InputSettlerCompactLIFI settler)
    {
        deployCompact();
        settler = deploySettler(initialOwner, expectedSettlerAddress);

        deployOutputSettlerSimple();
        deployAlwaysOkAllocaor();
        deployAlwaysYesOracle();
    }

    function deploySettler(
        address initialOwner,
        address expectedSettlerAddress
    ) internal returns (InputSettlerCompactLIFI settler) {
        bool isSettlerDeployed = address(expectedSettlerAddress).code.length !=
            0;

        if (!isSettlerDeployed) {
            settler = new InputSettlerCompactLIFI{salt: inputSettlerSalt}(
                COMPACT,
                initialOwner
            );

            if (expectedSettlerAddress != address(settler)) {
                revert NotExpectedAddress(
                    "settler",
                    expectedSettlerAddress,
                    address(settler)
                );
            }
            return settler;
        }
        return InputSettlerCompactLIFI(expectedSettlerAddress);
    }

    function deployCompact() internal {
        bool isCompactDeployed = COMPACT.code.length != 0;

        if (!isCompactDeployed) {
            address compact = address(
                new TheCompact{
                    salt: 0x0000000000000000000000000000000000000000a762b8ea350d5a4d430100e0
                }()
            );

            if (COMPACT != compact)
                revert NotExpectedAddress("compact", COMPACT, compact);
        }
    }

    function deployOutputSettlerSimple()
        internal
        returns (OutputSettlerSimple filler)
    {
        address expectedAddress = getExpectedCreate2Address(
            outputSettlerSalt, // salt
            type(OutputSettlerSimple).creationCode,
            hex""
        );
        bool isFillerDeployed = address(expectedAddress).code.length != 0;

        if (!isFillerDeployed)
            return filler = new OutputSettlerSimple{salt: outputSettlerSalt}();
        return OutputSettlerSimple(expectedAddress);
    }

    function deployAlwaysOkAllocaor()
        internal
        returns (AlwaysOKAllocator allocator, uint96 allocatorId)
    {
        address expectedAddress = getExpectedCreate2Address(
            bytes32(uint256(0)), // salt
            type(AlwaysOKAllocator).creationCode,
            hex""
        );
        bool isAllocatorDeployed = address(expectedAddress).code.length != 0;

        if (!isAllocatorDeployed)
            allocator = new AlwaysOKAllocator{salt: bytes32(uint256(0))}();
        else allocator = AlwaysOKAllocator(expectedAddress);

        allocatorId = IdLib.toAllocatorId(address(allocator));

        bytes32 storageSlotKey;
        assembly {
            storageSlotKey := or(
                _ALLOCATOR_BY_ALLOCATOR_ID_SLOT_SEED,
                allocatorId
            )
        }

        bytes32 storageSlotValue = vm.load(COMPACT, storageSlotKey);
        if (storageSlotValue == bytes32(0)) {
            uint96 registeredAllocatorId = TheCompact(COMPACT)
                .__registerAllocator(address(allocator), "");
            assert(registeredAllocatorId == allocatorId);
        }
    }

    function deployAlwaysYesOracle() internal returns (AlwaysYesOracle oracle) {
        address expectedAddress = getExpectedCreate2Address(
            bytes32(uint256(0)), // salt
            type(AlwaysYesOracle).creationCode,
            hex""
        );
        bool isOracleDeployed = address(expectedAddress).code.length != 0;

        if (!isOracleDeployed)
            return oracle = new AlwaysYesOracle{salt: bytes32(uint256(0))}();
        return AlwaysYesOracle(expectedAddress);
    }
}
