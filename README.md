# Cross-Cats: Intent based cross-chain swaps

Cross-cats is an intent based cross-chain swap protocol. Users sign intents: What asset they want, how they want etc, etc. which is claimed and then delivered by solvers.

## Structure of Cross-Cats

![System Diagram](./cross-cats-0-2.svg)
Refer to the SVG diagram chart.

Cross Cats consists of 2 core contracts: Reactor and Oracle. A Reactor contains logic to handle the initiation of an order. Each Reactor implementation may have different order types. Oracles are in charge of telling Reactors that an order fulfillment has happened. Depending on the order type and assets, a local oracle and remote oracle may be required to prove orders. Local oracles exist on the same chain as the Reactor while remote oracles exist on another chain.


### Reactor

Reactors are located in `src/reactors`. `BaseReactor.sol` contains shared logic between reactors while `LimitOrderReactor.sol` and `DutchOrderReactor.sol` implement logic for limit orders and dutch orders respectively. Reactors are in charge of the core intent flow:
- Collecting assets & Claiming Intents
- Disputing Intents & Verifying orders against oracles
- and secondary logic like selling & buying intents.

#### Inputs vs Outputs

Orders have 2 lists of tokens – Inputs and Outputs – to describe which assets (inputs) the signer is offering and which assets the solver should provide in exchange (outputs).
The Reactor, or settlement contract, always sits on the origin chain together with the input tokens. The Reactor and chain is specified in the order as `settlementContract` and `originChainId`.

If a chain does not have a reactor, it is not possible to initiate orders on the chain or let the chain's assets be inputs. Oracles may still support verifying assets on the chain, as such they can be set as outputs.

Outputs are divided into 2 classes:
1. VM (including EVM) outputs.
2. Non-VM (including Bitcoin) outputs

VM outputs are proved using two oracles, a remote filler oracle and a local oracle. On the destination chain, the solver calls the filler oracle to settle the outputs to the user. Then, the filler oracle sends a cross-chain message to the local oracle to inform it that the fill happened. This allows one to prove that the outputs were delivered on the remote chain. In the order, the filler oracle is described as the remoteOracle.

Non-VM outputs are proved using only a single oracle: A local oracle – often a light client oracle – that has the ability to verify that a transaction that matches the output was made. For such an order, it is required that the `remoteOracle` & `chainId` is set to the same as the `localOracle` & `originChainId`.

#### ChainIds

OriginChainId is always the chainId that the chain believes it is (`block.chainid`). While the remote chainId is defined by the localOracle, it is good practise to implement it as the remote chain's `block.chainid` or equivalent.

### Oracle

Oracles are located in `src/oracles`. `BaseOracle.sol` implement shared logic between all oracles, this mainly consists of messaging and standardizing proven outputs are exposed. `BridgeOracle.sol` and `BitcoinOracle.sol` implements logic for verifying VM payments and Bitcoin TXOs respectively. The Bridge Oracle allows solvers to fill outputs, outputs can be proven by calling `fill(...)`, while the Bitcoin Oracle allows solvers to verify outputs, outputs can be verified by calling `verify(...)`. By extending oracles with the `GARP/GeneralisedIncentivesOracle.sol`, oracles get the ability to relay & receive proofs to & from other oracles.

### Bitcoin SPV (Light) Client

This repository depends on the SPV client Bitcoin Prism. This repository does not contain it but depends on it as a submodule under `lib/bitcoinprism-evm`

### Helpers and Libraries

The repository contains several helpers which can found in either `src/libs` or `src/reactors/helpers`. If a helper is in `src/libs` it implies it has been designed to be general purpose while if it is in `src/reactors/helpers` it is integral to the function of the reactors.

## Usage

### Build

```shell
forge build [--sizes]
```

### Test

```shell
forge test [--fuzz-runs 10000] [--gas-report --fuzz-seed 10]
```

### Coverage

```shell
forge coverage --ir-minimum [--report lcov]
```