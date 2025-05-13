import {
  Environment,
  StandardRelayerApp,
  StandardRelayerContext,
} from "@wormhole-foundation/relayer-engine";

import { CHAIN_ID_APTOS } from "@certusone/wormhole-sdk";
import { writeFileSync } from "fs";

async function listen() {
  let app = new StandardRelayerApp<StandardRelayerContext>(
    Environment.TESTNET,
    // Other app specific config options can be set here for things
    // like retries, logger, or redis connection settings
    {
      name: "APTOS_TO_EVM",
    }
  );
  const emitterAddress =
    "00000000000000000000000000000000000000000000000000000000000000d9";

  let vaaParsed = await app.fetchVaa(CHAIN_ID_APTOS, emitterAddress, "3");

  console.log(`------\nGot a VAA\n------\n `);

  let signedVaa = vaaParsed.bytes;
  console.log("signedVaa: ", Buffer.from(signedVaa).toString("hex"));

  writeFileSync(
    "./vaa.json",
    JSON.stringify({ signedVaa: vaaParsed.bytes.toString() })
  );
  console.log("VAA saved to vaa.json");
}

listen();
