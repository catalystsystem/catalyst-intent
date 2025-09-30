// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import { InputSettlerCompactLIFI } from "../../src/input/compact/InputSettlerCompactLIFI.sol";

event PackagePublished(uint32 nonce, bytes payload, uint8 consistencyLevel);

import { InputSettlerCompactTestCrossChain } from "OIF/test/integration/SettlerCompact.crosschain.t.sol";

contract InputSettlerCompactLIFITestCrossChain is InputSettlerCompactTestCrossChain {
    function setUp() public virtual override {
        super.setUp();
        inputSettlerCompact = address(new InputSettlerCompactLIFI(address(theCompact), address(0)));
    }
}
