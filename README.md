# Cross-Cats: Intent based cross-chain swaps

Cross-cats is an intent based cross-chain swap protocol. Users sign intents: What asset they want, how they want etc, etc. which is claimed and then delivered by solvers.

## Repository Structure

Refer to the SVG diagram chart.

Cross Cats consists of 2 core contract: Reactor and Oracle. A reactor is a specific implemented order type. Generally they share a lot of implementation details but the way the order is treated is different. Oracles surface proofs the same way but the way they prove actions took place may be different.

### Reactor

Reactors are located in `src/reactors`. The file `BaseReactor.sol` has the shared common base logic of reactors while `LimitOrderReactor.sol` and `DutchOrderReactor.sol` implements logic for understanding limit orders and dutch orders respectively. These reactors are in charge of the core intent flow:
- Collecting assets & Claiming Intents
- Disputing Intents & Verifying orders against oracles
- and secondary logic like selling & buying intents.

### Oracle

Oracles are located in `src/oracles`. The file `BaseOracle.sol` implements shared logic between all oracles, this consists of some messaging, and exposing proved outputs. `BridgeOracle.sol` and `BitcoinOracle.sol` implements logic for verifying VM payments and Bitcoin TXOs respectively.

The oracles are capable of sending their proofs to other oracles and those oracles will now expose a proven output for a remote oracle.

### Bitcoin SPV (Light) Client

This repository depends on the SPV client Bitcoin Prism. This repository does not contain it but depends on it as a submodule under `lib/bitcoinprism-evm`

## Usage

### Build

```shell
forge build
```

### Test

```shell
forge test
```