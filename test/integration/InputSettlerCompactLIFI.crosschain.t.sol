// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { InputSettlerCompactLIFIWithDeposit } from "../../src/input/compact/InputSettlerCompactLIFIWithDeposit.sol";

import { MandateOutput, MandateOutputType } from "OIF/src/input/types/MandateOutputType.sol";
import { StandardOrder, StandardOrderType } from "OIF/src/input/types/StandardOrderType.sol";

import { MandateOutputEncodingLib } from "OIF/src/libs/MandateOutputEncodingLib.sol";
import { MessageEncodingLib } from "OIF/src/libs/MessageEncodingLib.sol";

event PackagePublished(uint32 nonce, bytes payload, uint8 consistencyLevel);

import { InputSettlerCompactTestCrossChain } from "OIF/test/integration/SettlerCompact.crosschain.t.sol";

contract InputSettlerCompactLIFITestCrossChain is InputSettlerCompactTestCrossChain {
    function setUp() public virtual override {
        super.setUp();
        inputSettlerCompact = address(new InputSettlerCompactLIFIWithDeposit(address(theCompact), address(0)));
    }
}
