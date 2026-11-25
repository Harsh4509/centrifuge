# Test data

Seeding a deployment with something to exercise. Run everything from the repository root.

The seeding scripts themselves went with the v1 vaults: `TestData.s.sol` and `BaseTestData.s.sol` drove the
v1 async and sync vault flows, and nothing has replaced them for the Vault Development Kit yet. `script/anvil/anvil.sh`
therefore stops at the deployment. What remains here is the troubleshooting cookbook, which is about a
deployed chain rather than about any one script.

Networks are named, not URLs: `--rpc-url local-a` resolves through `foundry.toml` `[rpc_endpoints]`, and the
script reads `env/anvil-<id>/local-a.json` because that config names the chain id the RPC answers with.

The base branch's only chains are the local pair `script/anvil/anvil.sh` brings up, which need no secrets.
Running this against a chain that outlives the process is done from `live`, where those configs are.

---

## Troubleshooting

`cast` resolves the same `[rpc_endpoints]` aliases as `forge script`, so these take a network name too.
Contract addresses come out of `env/<environment>/<network>.json` → `contracts`.

```bash
# Would wiring this adapter to the remote centrifugeId overwrite anything? True once the chain has a
# destination or the bridge id in the data already has a source; the OpsGuardian refuses to wire while true
cast call $AXELAR_ADAPTER "isWired(uint16,bytes)(bool)" 2 \
  $(cast abi-encode "f(string,string)" "<axelar-chain-id>" "<remote-adapter-address>") --rpc-url local-a

# Does a pool still have subsidies to pay for outgoing messages?
cast call $SUBSIDY_MANAGER "subsidies(uint64)(uint256)" 562949953512312 --rpc-url local-a

# What did a transaction actually do?
cast receipt <tx-hash> --rpc-url local-a
cast run <tx-hash> --rpc-url local-a
```

Cross-chain messages are relayed by the adapter's own network, so a message that left the hub is tracked in
that adapter's explorer, keyed by the sender address:

- **Axelar**: https://testnet.axelarscan.io/gmp/search?senderAddress=<sender>
- **LayerZero**: https://testnet.layerzeroscan.com/address/<sender>
- **Chainlink CCIP**: https://ccip.chain.link/address/<sender>
- **Hyperlane**: https://explorer.hyperlane.xyz/?search=<sender>
