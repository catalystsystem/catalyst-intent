// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { LIFISettlerCompactWithDeposit } from "../../src/settlers/compact/LIFISettlerCompactWithDeposit.sol";

import { MandateOutput, MandateOutputType } from "OIF/src/settlers/types/MandateOutputType.sol";
import { StandardOrder, StandardOrderType } from "OIF/src/settlers/types/StandardOrderType.sol";

import { MandateOutputEncodingLib } from "OIF/src/libs/MandateOutputEncodingLib.sol";
import { MessageEncodingLib } from "OIF/src/libs/MessageEncodingLib.sol";

event PackagePublished(uint32 nonce, bytes payload, uint8 consistencyLevel);

import { SettlerCompactTestCrossChain } from "OIF/test/integration/SettlerCompact.crosschain.t.sol";

contract LIFISettlerCompactTestCrossChain is SettlerCompactTestCrossChain {
    function setUp() public virtual override {
        super.setUp();
        settlerCompact = address(new LIFISettlerCompactWithDeposit(address(theCompact), address(0)));
    }
}
