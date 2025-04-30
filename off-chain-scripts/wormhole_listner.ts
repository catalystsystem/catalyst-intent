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
    "00000000000000000000000000000000000000000000000000000000000000d4";

  let vaaParsed = await app.fetchVaa(CHAIN_ID_APTOS, emitterAddress, "1");

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

//01000000000100f980cdcc5b24eb63e8188e85ffcf9da4e4dd051719b8020b84bb0de354ca86466a6a322d5065f8a8505a9229937c94a9dd04520e6ade629b44acd350d620081600680d57f700000000001600000000000000000000000000000000000000000000000000000000000000d40000000000000000009c1ddd3992cea0ed02c01a2baf35a95db0c0841ed18be74e28fdffce1ec8331f000100a80000000000000000000000007111c16d9e779f4bc04e28e988ba81fb2204b7d099d6c3f67c155b30fb9c7d62c2a97f5ad22970f7047a279a91bc0f9da923de95680d547369091fbab5f7d635ee7ac5098cf0c1efbe31d68fec0f2cd565e8d168daf52832000000000000000000000000000000000000000000000000000000000000c35025303d0e8ae305b0a2c2bc79956b6d47d258293d5d2cb50596174c2e90ce055b00000000
