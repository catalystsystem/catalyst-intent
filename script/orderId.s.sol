// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import { Script } from "forge-std/Script.sol";

import { InputSettlerCompactLIFI } from "../src/input/compact/InputSettlerCompactLIFI.sol";
import { MandateOutput } from "OIF/src/input/types/MandateOutputType.sol";
import { StandardOrder } from "OIF/src/input/types/StandardOrderType.sol";

/**
 * @notice Easily deploy contracts across multiple chains.
 */
contract GetOrderId is Script {
    function run() external returns (bytes32 orderId) {
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [36480414457181834686435859733604505384509859462345317876249814483837321507384, 20000];

        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = MandateOutput({
            oracle: 0x000000000000000000000000009379002e03ec0017000030002f63d9d44d0128,
            settler: 0x000000000000000000000000000000324f76f52224dabad500f7d60c00344a68,
            chainId: 84532,
            token: 0x000000000000000000000000036cbd53842c5426634e7929541ec2318f3dcf7e,
            amount: 20000,
            recipient: 0x000000000000000000000000529cebf485dee1d68073afb75244022f048b0157,
            callbackData: hex"",
            context: hex""
        });
        StandardOrder memory order = StandardOrder({
            user: 0x529CEbF485DeE1d68073AFB75244022F048B0157,
            nonce: 1646493959,
            originChainId: 11155111,
            expires: 1753714798,
            fillDeadline: 1753714798,
            inputOracle: 0x009379002e03ec0017000030002f63d9d44d0128,
            inputs: inputs,
            outputs: outputs
        });

        vm.broadcast();
        orderId = InputSettlerCompactLIFI(0x000000006B10B0C15dC80dCE37d52aC76dA81000).orderIdentifier(order);
    }
}
