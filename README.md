# Cross-Cats: Intent based cross-chain swaps

Cross-cats is an intent based cross-chain swap protocol. Users sign intents: What asset they want, how they want etc, etc. which is claimed and then delivered by solvers.

## Structure of Cross-Cats

![System Diagram](./cross-cats-0-2.svg)
Refer to the SVG diagram chart.

Cross Cats consists of 2 core contract: Reactor and Oracle. A Reactor contains logic to handle the initiation of an order. Each Reactor implementation may have different order types. Oracles are in charge of telling Reactors that an order fulfillment has happened. Depending on the order type and assets, there may be a local oracle and remote oracle may be required to prove orders. Local oracles exist on the same chain as the Reactor while remote oracles exists on another chain.


### Reactor

Reactors are located in `src/reactors`. `BaseReactor.sol` contains shared logic between reactors while `LimitOrderReactor.sol` and `DutchOrderReactor.sol` implements logic for limit orders and dutch orders respectively. Reactors are in charge of the core intent flow:
- Collecting assets & Claiming Intents
- Disputing Intents & Verifying orders against oracles
- and secondary logic like selling & buying intents.

#### Inputs vs Outputs

Orders have 2 lists of tokens – Inputs and Outputs – to describe which assets (inputs) the signer is offering and which assets the solver should prove in exchange (outputs).
The Reactor, or settlement contract, always sits on the origin chain together with the input tokens. The Reactor and chain is specified in the order as the `settlementContract` and the `originChainId`.

If a chain does not have a reactor, it is not possible to initiate orders on the chain or configure the chain's assest as inputs. This does not make it impossible to set the chain's assets as outputs may still be provable through compatible oracles.

Outputs are divided into 2 classes:
1. VM (including EVM) outputs.
2. Non-VM (including Bitcoin) outputs

VM outputs are proved with the use of 2 oracles, a filler oracle and a local oracle. On the destination chain, the solver calls the filler oracle to settle the outputs to the user. Then, the filler oracle sends a cross-chain message to the local oracle that the fill happened. This allows proving that the outputs were delivered on a remote chain. In the order, the filler oracle is described as the remoteOracle.

Non-VM outputs are proved using only a single oracle: A local oracle – often a light client oracle or similarly. This oracle should provide the ability to verify that a transaction that matches the output was made. For such an order, it is required that the `remoteOracle` & `chainId` is set to the same as the `localOracle` & `originChainId`.

### Oracle

Oracles are located in `src/oracles`. `BaseOracle.sol` implements shared logic between all oracles, this mainly consists of some messaging and standardizing how to expose proven outputs. `BridgeOracle.sol` and `BitcoinOracle.sol` implements logic for verifying VM payments and Bitcoin TXOs respectively. The Bridge Oracle allows solvers to fill outputs, outputs can be proven by calling `fill(...)`, while the Bitcoin Oracle allows solvers to verify outputs, outputs can be verified by calling `verify(...)`. By inheriting base oracle both oracles are able to relay & receive proofs to & from other oracles.

### Bitcoin SPV (Light) Client

This repository depends on the SPV client Bitcoin Prism. This repository does not contain it but depends on it as a submodule under `lib/bitcoinprism-evm`

### Helpers and Libraries

The repository contains several helpers which can found in either `src/libs` or `src/reactors/helpers`. If a helper is in `src/libs` it implies it has been designed to be general purpose while if it is in `src/reactors/helpers` it is integral to the function of the reactors.

## Usage

### Build

```shell
forge build (--sizes)
```

### Test

```shell
forge test (--fuzz-runs 10000) (--gas-report --fuzz-seed 10)
```

### Coverage

```shell
forge coverage --ir-minimum (--report lcov)
```