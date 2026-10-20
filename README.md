# GoatPro (GPRO)

GoatPro is an ERC-20 token with a fixed supply of **1,000,000,000 GPRO** and
**18 decimals**. Its constructor mints all **1000000000000000000000000000**
base units (`10^27`) once to `msg.sender`, the immediate deployer.

The deployable contract is `src/GoatPro.sol:GoatPro`. It uses the vendored
OpenZeppelin ERC-20 implementation. The only added behavior is the constructor
mint and the public `INITIAL_SUPPLY` constant.

## Behavior and assumptions

- Transfers deliver the exact requested amount; there are no token taxes, burns,
  rebases, transfer limits, or recipient callbacks.
- There is no owner, administrator, minter, pause, blocklist, seizure mechanism,
  proxy, initializer, or upgrade path. Supply cannot change after construction.
- Standard `transfer`, `approve`, and `transferFrom` return `true` on success and
  revert with OpenZeppelin ERC-6093 custom errors on invalid operations.
- Zero-value transfers to valid addresses succeed and emit `Transfer`.
  Transfers to the zero address and approvals to the zero spender revert.
- Approvals replace the existing allowance. Finite allowances decrease when spent;
  `type(uint256).max` is an unlimited allowance and is not decreased.
  `approve` emits `Approval`; this OpenZeppelin version does not emit another
  `Approval` when `transferFrom` spends an allowance. Read `allowance()` for its
  current value.
- No oracle, router, chain address, external service, or configuration is needed.
  The token has no time, block-number, randomness, or sequencer dependency.

## Build and test

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x2201b3dd98fde2f2a034c6e548d17c38fb7323d51850587b38fd3563f5ca97cc forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files under `lib/`;
no dependency installation, network connection, environment configuration, fork,
FFI, or filesystem cheatcode is required to run the tests. The compiler is pinned
by version in `foundry.toml`; the verifier supplies that compiler offline.
See `DEPENDENCIES.md` for the exact dependency versions and provenance.

Compilation uses the Cancun EVM target, optimizer enabled with 200 runs, and
`bytecode_hash = "none"`. The token requires no separately linked libraries.

Tests cover metadata, the single constructor mint event, direct and CREATE2
factory deployment, exact distribution and claim transfers, transfers in both
pool directions, balances, approvals, revocation, unlimited allowances,
zero-value and self-transfers, invalid recipients, insufficient balances and
allowances, failure atomicity, and rejected administrative selectors.
Fuzz tests check valid and invalid amounts, and stateful invariants check
conservation across sequences of transfers and approvals.

The pool transfer fixture tests token accounting only; it is not a Uniswap pool
or a swap-price simulation. The supplied protected harness performs the actual
launch and Uniswap integration checks in the separate verifier. It depends on
the launch infrastructure and manifest supplied by that verifier.

## Deployment parameters and responsibilities

| Parameter | Value |
| --- | --- |
| Solidity identifier | `GoatPro` |
| Constructor arguments | None (`[]`) |
| Constructor native value | `0` |
| Token name / symbol | `GoatPro` / `GPRO` |
| Decimals | `18` |
| Total supply, base units | `1000000000000000000000000000` |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Intended chain, per assignment | Robinhood Chain, chain ID `4663` |
| Additional application contracts | None |

For a factory launch, the factory receives the entire supply, even when another
wallet called the factory. The token does not use `tx.origin`, reserve a share,
distribute funds, or create a pool. The launch system is responsible for its
10% distributor allocation, 80% pool allocation, and 10% remainder according to
the assignment's launch policy. Those allocations and pool fees are external
launch settings, not token transfer fees.

The separate launch step writes `launch.json`, chooses the factory deployment
salt, deploys the compiled creation bytecode with no arguments, distributes the
supply, and publishes the deployed address and source verification. This project
contains no signing or broadcasting script and performs no transactions.
The launch operator must use the pinned compiler/settings and confirm the
initial supply, recipient, and metadata against the built artifact.

## After launch

There are no setters, ownership handovers, or initialization calls. Holders
control transfers and allowances; the original deployer has no special rights.
Wallets should display amounts with 18 decimals and manage spender approvals.
When replacing a nonzero allowance, revoke it and wait for confirmation before
granting the replacement to reduce the usual ERC-20 approval ordering risk.

The token cannot recover funds sent to an incorrect address or to its own
contract, and cannot rescue unrelated assets sent to it. Ordinary native-currency
payments revert. The launch operator remains responsible for distribution,
pool setup, and source verification. Passing local tests is not an independent
security audit; the network's separate adversarial review remains a release step.
