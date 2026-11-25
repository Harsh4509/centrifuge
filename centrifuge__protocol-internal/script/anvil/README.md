# Local chains

Two anvil chains with the protocol deployed on both, the way a real chain gets it: through the DeployGate,
`commit()` and `deploy()` as separate forge runs.

```bash
./script/anvil/anvil.sh
```

Nothing external is needed — no API key, no credentials, no network. This is what `ci.yml` runs on every PR,
and it is the only deployment the base branch makes: everything that outlives a process is deployed from
`live`.

## Why it is not a fork

It used to fork Sepolia, which meant an Alchemy key, which meant credentials in CI. A fork was only ever
providing three things, and none of them need one:

| | On a bare chain |
| --- | --- |
| CreateX | `setUpCreateXFactory()` can only `vm.etch` it, which lives and dies with the simulation, so `anvil.sh` puts the real runtime code at its canonical address first |
| the DeployGate | deploys itself through CreateX, in the run |
| messaging endpoints | `FullDeployer` requires code at each one before it will deploy an adapter against it; `anvil.sh` stubs them with the same bytecode `test/integration/Deployer.t.sol` etches |

## Configs: what goes in, what comes out

An `env/<environment>/<network>.json` holds two halves. The chain half — `network` and `adapters` — is
input, written by hand. The `contracts` half is output, and a deploy script records itself into it as it
runs. Both live in one file, because a script reading a deployment back through `Env.load()` needs the chain
half to find the protocol recorded beside it.

The fixtures here are the input half only:

```
$ jq -c 'keys' script/anvil/env/local-a.json
["adapters","network"]
```

A run copies them into `env/anvil-<id>/` and deploys against the copies. That copy is what *creates* the output
config: `LaunchDeployer` merges its addresses into the chain half sitting there. Without it there would be no
complete config for the run to produce — writing a contracts-only file would fail the chain-half parse on the
next read.

`env/anvil-*/` is gitignored, so the run's record stays out of the tree, and these fixtures come out of a
deployment byte-identical. That separation is not about churn in the addresses: with a fixed `deploymentId` the
addresses are reproducible to the byte. It is about the rest — `timestamp` moves every run and `blockNumber`
is whatever block the deploy landed in — because a deployment record is about one run, and these files are
not.

Both directories are `Chains.configRoots()` entries, and a run's own copy wins over the fixture, which is why it reads its own
output and a fresh clone still finds two chains for the schema tests to walk.

| | |
| --- | --- |
| `local-a.json` | chain 31337 on :8545, centrifugeId 1, takes the vault stack (`network.vaults`) |
| `local-b.json` | chain 31338 on :8546, centrifugeId 2, does not |
| `connections.json` | both chains wired to each other over all three adapters |

The endpoint addresses in them are placeholders: nothing is deployed there, `anvil.sh` puts a stub at each,
and the adapters are deployed and wired against those. The admin is anvil's second account, so the guardians
can be driven from a key everyone has.

## The two shapes of launch

`local-a` sets `network.vaults`, so its launch carries the spoke half of the Vault Development Kit
(`VaultFactory`, `VaultRequestRouter`, the shared oracle, policies and liquidity route). `VaultFactory` and
the vault are over EIP-170, and anvil has no hardfork that activates EIP-7907, so `anvil.sh` starts that one
chain with `--code-size-limit 65536`, the 7907 limit, standing in for a chain that has it. `local-b` names no
`vaults` and keeps anvil's EIP-170 default, which is what proves a launch without the vault stack still fits
a chain that has not activated 7907: anything over 24,576 bytes in it would fail that run.
