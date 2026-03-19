# LI.FI Intent

LI.FI Intent is a cross-chain swap protocol built on the [Open Intents Framework (OIF)](https://github.com/openintentsframework/oif-contracts). Users sign customisable intents describing desired assets, delivery parameters, and validation logic. Solvers permissionlessly fill and deliver these intents across chains.

This repository contains the smart contract layer. For the solver implementation, see the [OIF Solvers repo](https://github.com/openintentsframework/oif-solvers).

## Architecture

The system separates input collection from output delivery, supporting both Output First and Input Second flows through [Resource Locks](https://docs.onebalance.io/concepts/resource-locks) and traditional escrows in a single deployment.

Three core modules make this work:

- **InputSettler** sits on the origin chain and finalises intents. It validates that a solver filled outputs (using the oracle) and releases input assets to the filler
- **OutputSettler** sits on the destination chain and allows solvers to fill outputs. It exposes attestation state via `IPayloadValidator.hasAttested()`
- **Oracle** bridges proof of filled outputs from the destination chain back to the origin chain. Polymer (IBC-based) and Wormhole (VAA-based) are both supported

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ORIGIN CHAIN                                   │
│                                                                             │
│   ┌──────────┐      1. Sign intent &       ┌───────────────────────┐       │
│   │   User   │ ──── lock input assets ────► │     InputSettler      │       │
│   │ (Sponsor) │                              │  (Compact or Escrow)  │       │
│   └──────────┘                              └───────────┬───────────┘       │
│                                                         │                   │
│                                              5. Validate│fills              │
│                                                         │                   │
│                                              ┌──────────┴──────────┐       │
│                                              │       Oracle        │       │
│                                              │   (receive proof)   │       │
│                                              └──────────▲──────────┘       │
└─────────────────────────────────────────────────────────┼───────────────────┘
                                                          │
           ┌──────────────┐                    4. Bridge proof
           │    Solver    │                   (Polymer / Wormhole)
           │   (Filler)   │                               │
           └──┬───────▲───┘                               │
              │       │                                   │
   2. Fill    │       │ 7. Release inputs                 │
   outputs    │       │    (minus fee)                    │
              │       │                                   │
┌─────────────┼───────┼───────────────────────────────────┼───────────────────┐
│             ▼       │         DESTINATION CHAIN          │                   │
│   ┌─────────────────┴─┐    3. Emit fill    ┌───────────┴──────────┐       │
│   │   OutputSettler    │ ──── proof ──────► │       Oracle        │       │
│   └────────┬──────────┘                     │  (generate proof)   │       │
│            │                                └─────────────────────┘       │
│            │ Deliver assets                                               │
│            ▼                                                              │
│   ┌─────────────────┐                                                     │
│   │    Recipient     │                                                     │
│   └─────────────────┘                                                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Protocol Flow

```
  User                InputSettler (Origin)        Solver          OutputSettler (Dest)      Oracle
   │                         │                       │                     │                   │
   │  Sign StandardOrder     │                       │                     │                   │
   │  & lock inputs          │                       │                     │                   │
   │ ──────────────────────► │                       │                     │                   │
   │                         │                       │                     │                   │
   │                         │  IntentRegistered     │                     │                   │
   │                         │  event                │                     │                   │
   │                         │ ─────────────────────►│                     │                   │
   │                         │                       │                     │                   │
   │                         │                       │  Fill outputs       │                   │
   │                         │                       │ ──────────────────► │                   │
   │                         │                       │                     │                   │
   │                         │                       │                     │  Generate proof   │
   │                         │                       │                     │ ────────────────► │
   │                         │                       │                     │                   │
   │                         │       Bridge proof to origin chain          │                   │
   │                         │ ◄──────────────────────────────────────────────────────────────│
   │                         │                       │                     │                   │
   │                         │  finalise() + proof   │                     │                   │
   │                         │ ◄─────────────────────│                     │                   │
   │                         │                       │                     │                   │
   │                         │  Release inputs       │                     │                   │
   │                         │  (minus gov fee)      │                     │                   │
   │                         │ ─────────────────────►│                     │                   │
   │                         │                       │                     │                   │
```

The same-chain shortcut (`openForAndFinalise()`) collapses this entire flow into a single transaction. The solver fills the output via a reentrant callback during the open step, so no oracle bridging is needed.

## Repository Structure

```
src/
  input/
    compact/
      InputSettlerCompactLIFI.sol    # Input settler using The Compact (ERC-6909 resource locks)
    escrow/
      InputSettlerEscrowLIFI.sol     # Input settler using ERC-20 escrow
  libs/
    GovernanceFee.sol                # Timelocked fee governance (7-day delay, 5% max)
    RegisterIntentLib.sol            # Helper for registering intents via The Compact

script/
  deploy.s.sol                       # Multi-chain CREATE2 deployment
  multichain.s.sol                   # Base helper for chain iteration
  polymer.s.sol                      # Polymer oracle deployment
  wormhole.s.sol                     # Wormhole oracle deployment
  orderId.s.sol                      # Order ID computation utility

test/
  input/
    compact/                         # Unit tests for Compact settler
    escrow/                          # Unit tests for Escrow settler
  integration/
    InputSettler7683LIFI.samechain.t.sol      # Same-chain swap end-to-end
    InputSettlerCompactLIFI.crosschain.t.sol  # Cross-chain Compact end-to-end
  lib/
    RegisterIntentLib.t.sol          # RegisterIntentLib unit tests
```

## Input Settlers

Two settler implementations handle input asset locking on the origin chain.

### Compact Settler

`InputSettlerCompactLIFI` uses Uniswap's [The Compact](https://github.com/Uniswap/the-compact), an ERC-6909 resource lock system. Users pre-deposit assets and sign resource lock attestations. Solvers claim via `COMPACT.batchClaim()` after proving output delivery.

Key functions:

- `broadcast()` validates a pre-registered intent and emits `IntentRegistered` for solver discovery (gasless registration path)
- `finalise()` releases locked inputs to the solver (caller must be the order owner)
- `finaliseWithSignature()` permits another address to claim on the solver's behalf using EIP-712 authorisation

### Escrow Settler

`InputSettlerEscrowLIFI` uses explicit ERC-20 escrow. Users deposit tokens into the settler contract via Permit2 or ERC-3009 signatures.

Key functions:

- `openForAndFinalise()` provides an atomic same-chain swap path, combining deposit, claim, and validation in one transaction
- `finalise()` and `finaliseWithSignature()` handle the standard cross-chain settlement flow

## Governance Fee

Both settlers inherit `GovernanceFee`, which applies a protocol fee on input releases. The fee has a 5% maximum cap and a 7-day timelock on changes, so governance cannot alter fees on in-flight orders. The owner calls `setGovernanceFee()` to schedule a change, then `applyGovernanceFee()` after the delay to activate it.

## Oracle Integrations

### Polymer

Uses IBC-based proofs via `PolymerOracle` or `PolymerOracleMapped` (with chain ID mapping). Deployed at a single address across supported chains.

### Wormhole

Uses VAA-based message verification via `WormholeOracle`. Requires per-chain deployment with Wormhole-specific chain ID mappings.

## Solver Selection

For multi-output orders, the solver filling the first output becomes the order owner and can claim funds after settlement.

- If multiple solvers fill different outputs, the first solver decides who gets paid
- A filler may fill the first output but not the remaining, which blocks other solvers from completing the order. Intent issuers should make the first output the most valuable
- Dutch auctions apply to the first output only
- All outputs may be solved atomically but in a random order

## Order Purchasing / Underwriting

The OIF supports underwriting (described as order purchasing in the contracts). This serves two purposes: speeding up solver capital rotation by borrowing from less risk-averse solvers, and allowing users acting as solvers to receive assets faster for a better experience.

## Deployments

Deployed via CREATE2 for deterministic addresses across all supported chains.

| Contract | Address |
|---|---|
| The Compact | `0x00000000000000171ede64904551eeDF3C6C9788` |
| Input Settler Compact | `0x0000000000cd5f7fDEc90a03a31F79E5Fbc6A9Cf` |
| Input Settler Escrow | `0x000025c3226C00B2Cdc200005a1600509f4e00C0` |
| Output Settler | `0x0000000000eC36B683C2E6AC89e9A75989C22a2e` |
| Polymer Oracle (Testnet) | `0x00d5b500ECa100F7cdeDC800eC631Aca00BaAC00` |
| Polymer Oracle (Mainnet) | `0x0000006ea400569c0040d6e5ba651c00848409be` |

## Integration

By integrating LI.FI intents as a solver or intent issuer, you also integrate with the broader OIF ecosystem. See the [LI.FI Intents documentation](https://docs.li.fi/lifi-intents/introduction) for integration guides.

For more on the OIF itself: [OIF Contracts Repository](https://github.com/openintentsframework/oif-contracts)

## Development

### Build

```shell
forge build [--sizes]
```

### Test

```shell
forge test [--fuzz-runs 10000] [--gas-report --fuzz-seed 10]
```

### Gas Report

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

### Environment Setup

Copy `.env.example` and set RPC URLs for each target chain:

```shell
cp .env.example .env
```

## Dictionary

- **Lock** is an escrow that provides system participants a claim to an asset if a given action is performed. A lock can be a simple escrow or a resource lock
- **Intent** is a description of a desired state change. Within the OIF, this is an asset swap (input for output) but could also be logic execution like gas sponsoring
- **Inputs** are the assets released from a lock after outputs have been proven delivered. The sponsor of an order pays these
- **Outputs** are the assets that must be paid to collect inputs from an order
- **Input Chain** is the chain where input assets originate (there may be multiple)
- **Output Chain** is the chain where output assets are paid (there may be multiple)
- **User** is the end user of the protocol, and the sponsor in most cases
- **Solver** is an external entity that facilitates swaps for users, and the filler in most cases
- **Sponsor** provides the input assets on the input chain and receives desired assets (outputs) first, then pays (inputs) second
- **Filler** provides assets on the output chain and executes swaps. They pay (outputs) first and collect (inputs) second

## License Notice

This project is licensed under the **[GNU Lesser General Public License v3.0 only (LGPL-3.0-only)](/LICENSE)**.

It also uses the following third-party libraries:

- **[OIF](https://github.com/openintentsframework/oif-contracts)** licensed under the [MIT License](https://opensource.org/licenses/MIT)
- **[Solady](https://github.com/Vectorized/solady)** licensed under the [MIT License](https://opensource.org/licenses/MIT)

Each library is included under the terms of its respective license. Copies of the license texts can be found in their source files or original repositories.

When distributing this project, please ensure that all relevant license notices are preserved in accordance with their terms.
