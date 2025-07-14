# LI.FI Intent based cross-chain swaps

LI.FI Intent is a cross-chain swap protocol built with the Open Intents Framework, OIF. It allows users to sign intents: What asset they want, how they want etc, etc. which is claimed and then delivered by solvers.

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

## License Notice

This project is licensed under the **[GNU Lesser General Public License v3.0 only (LGPL-3.0-only)](/LICENSE)**.

It also uses the following third-party libraries:

- **[OIF](https://github.com/openintentsframework/oif-contracts)** – Licensed under the [MIT License](https://opensource.org/licenses/MIT)
- **[Solady](https://github.com/Vectorized/solady)** – Licensed under the [MIT License](https://opensource.org/licenses/MIT)

Each library is included under the terms of its respective license. Copies of the license texts can be found in their source files or original repositories.

When distributing this project, please ensure that all relevant license notices are preserved in accordance with their terms.
