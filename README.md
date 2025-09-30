# LI.FI Intent based cross-chain swaps

LI.FI Intent is a cross-chain swap protocol built with the Open Intents Framework, OIF. It allows users to sign intents: What asset they want, how they want etc, etc. which is claimed and then delivered by solvers.

## Deployments

Deployed addresses:
- Compact Address: `0x00000000000000171ede64904551eeDF3C6C9788`
- Input Settler Compact Address: `0x000000c9eC71B1a39055Ec631200ED0022140074`
- Input Settler Escrow Address: `0x000001bf3F3175BD007f3889b50000c7006E72c0`
- Output Settler Address: `0x00000000D7278408CE7a490015577c41e57143a5`
- Polymer Oracle Testnet: `0x00d5b500ECa100F7cdeDC800eC631Aca00BaAC00`
- Polymer Oracle Mainnet: `0x0000006ea400569c0040d6e5ba651c00848409be`

### Open Intents Framework

The OIF is a reference implementation of a modular and composable intent system. LI.FI intent is built as an implementation of it, meaning it is compatible and compliments any other OIF deployment.

For more documentation about the OIF: https://github.com/openintentsframework/oif-contracts

## Integration

By integrating LI.FI intents, either as a solver or as an intent issuer, you will also be integrating with the OIF: https://docs.li.fi/lifi-intents/introduction. 

## Usage

### Build

```shell
forge build [--sizes]
```

### Test

```shell
forge test [--fuzz-runs 10000] [--gas-report --fuzz-seed 10]
```

#### Gas report
```shell
forge test --gas-report
```

### Coverage

```shell
forge coverage --no-match-coverage "(script|test|wormhole/external/wormhole|wormhole/external/callworm/GettersGetter)" [--report lcov]
```

### Deploy

```shell
forge script deploy --sig "run(string[])" "[<chains>]" --account <account> --slow --multi --isolate --always-use-create-2-factory --verify --broadcast [-vvvv]
```

## License Notice

This project is licensed under the **[GNU Lesser General Public License v3.0 only (LGPL-3.0-only)](/LICENSE)**.

It also uses the following third-party libraries:

- **[OIF](https://github.com/openintentsframework/oif-contracts)** – Licensed under the [MIT License](https://opensource.org/licenses/MIT)
- **[Solady](https://github.com/Vectorized/solady)** – Licensed under the [MIT License](https://opensource.org/licenses/MIT)

Each library is included under the terms of its respective license. Copies of the license texts can be found in their source files or original repositories.

When distributing this project, please ensure that all relevant license notices are preserved in accordance with their terms.
