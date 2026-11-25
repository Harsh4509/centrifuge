# Statement source index

Each row locates records in the unchanged [statements file](statements.json). The identifiers and per-dimension levels remain in that file. Source links open the referenced document.

| Source document | Statement identifiers | Dimensions |
| --- | --- | --- |
| [Centrifuge_vdk_context_docs_final.md](Centrifuge_vdk_context_docs_final.md) | S1–S118 | tf, scope, known |
| [SPECIFICATION.md](SPECIFICATION.md) | S119–S362 | tf, scope, known |
| [src/token/hooks/HookPolicies.sol](../centrifuge__protocol-internal/src/token/hooks/HookPolicies.sol) | S363–S364 | tf |
| [src/token/hooks/ShareTokenHook.sol](../centrifuge__protocol-internal/src/token/hooks/ShareTokenHook.sol) | S365 | tf |
| [src/vaults/Vault.sol](../centrifuge__protocol-internal/src/vaults/Vault.sol) | S366–S370 | tf |
| [src/vaults/factories/VaultFactory.sol](../centrifuge__protocol-internal/src/vaults/factories/VaultFactory.sol) | S371 | tf |
| [src/vaults/hub/FeeRequestManager.sol](../centrifuge__protocol-internal/src/vaults/hub/FeeRequestManager.sol) | S372–S373 | tf, known |
| [src/vaults/hub/OrderBook.sol](../centrifuge__protocol-internal/src/vaults/hub/OrderBook.sol) | S374–S375 | tf |
| [src/vaults/libraries/BucketLib.sol](../centrifuge__protocol-internal/src/vaults/libraries/BucketLib.sol) | S376 | tf |
| [src/vaults/libraries/RoleCheckLib.sol](../centrifuge__protocol-internal/src/vaults/libraries/RoleCheckLib.sol) | S377 | tf |
| [src/vaults/libraries/VaultPricingLib.sol](../centrifuge__protocol-internal/src/vaults/libraries/VaultPricingLib.sol) | S378 | tf |
| [src/vaults/liquidity/BasinLiquidityRoute.sol](../centrifuge__protocol-internal/src/vaults/liquidity/BasinLiquidityRoute.sol) | S379 | tf |
| [src/vaults/liquidity/VaultLiquidityRoute.sol](../centrifuge__protocol-internal/src/vaults/liquidity/VaultLiquidityRoute.sol) | S380–S382 | tf, known |
| [src/vaults/messaging/VaultRequestRouter.sol](../centrifuge__protocol-internal/src/vaults/messaging/VaultRequestRouter.sol) | S383 | tf |
| [src/vaults/oracles/SpokeOracle.sol](../centrifuge__protocol-internal/src/vaults/oracles/SpokeOracle.sol) | S384 | tf |
| [src/vaults/policies/RequestPolicies.sol](../centrifuge__protocol-internal/src/vaults/policies/RequestPolicies.sol) | S385 | tf |
| [.claude/prompts/async-lifecycle-review.md](../centrifuge__protocol-internal/.claude/prompts/async-lifecycle-review.md) | S386–S387 | tf, known |
| [.claude/prompts/integration-boundary-review.md](../centrifuge__protocol-internal/.claude/prompts/integration-boundary-review.md) | S388–S391 | tf, known |
| [.claude/prompts/pool-isolation-review.md](../centrifuge__protocol-internal/.claude/prompts/pool-isolation-review.md) | S392–S396 | tf, known |
| [.claude/prompts/share-custody-review.md](../centrifuge__protocol-internal/.claude/prompts/share-custody-review.md) | S397–S402 | tf, known |
| [.claude/rules/coding-style.md](../centrifuge__protocol-internal/.claude/rules/coding-style.md) | S403–S407 | tf, known |
| [.claude/rules/comments.md](../centrifuge__protocol-internal/.claude/rules/comments.md) | S408–S410 | tf |
| [.claude/rules/deployment.md](../centrifuge__protocol-internal/.claude/rules/deployment.md) | S411–S421 | tf, known |
| [.claude/rules/formal-verification.md](../centrifuge__protocol-internal/.claude/rules/formal-verification.md) | S422–S423 | tf, known |
| [CLAUDE.md](../centrifuge__protocol-internal/CLAUDE.md) | S424–S430 | tf, known |
| [docs/SPECIFICATION.md](../centrifuge__protocol-internal/docs/SPECIFICATION.md) | S431–S605 | tf, known |
| [docs/audits/out-of-scope/README.md](../centrifuge__protocol-internal/docs/audits/out-of-scope/README.md) | S606–S607 | tf |
| [docs/audits/out-of-scope/cantina-bug-bounty.md](../centrifuge__protocol-internal/docs/audits/out-of-scope/cantina-bug-bounty.md) | S608–S745 | tf, known |
| [docs/audits/out-of-scope/vdk.md](../centrifuge__protocol-internal/docs/audits/out-of-scope/vdk.md) | S746–S801 | tf, known |
| [docs/vaults-policies.md](../centrifuge__protocol-internal/docs/vaults-policies.md) | S802–S932 | tf, known |
| [env/README.md](../centrifuge__protocol-internal/env/README.md) | S933–S934 | tf |
| [env/spell/006_migration_v3.1/README.md](../centrifuge__protocol-internal/env/spell/006_migration_v3.1/README.md) | S935–S941 | tf |
| [script/anvil/README.md](../centrifuge__protocol-internal/script/anvil/README.md) | S942 | tf |
| [script/checks/README.md](../centrifuge__protocol-internal/script/checks/README.md) | S943–S945 | tf |
| [script/checks/fix_imports.md](../centrifuge__protocol-internal/script/checks/fix_imports.md) | S946–S957 | tf, known |
| [script/deploy/README.md](../centrifuge__protocol-internal/script/deploy/README.md) | S958–S988 | tf, known |
| [script/testnet/README.md](../centrifuge__protocol-internal/script/testnet/README.md) | S989 | tf, known |
| [src/adapters/README.md](../centrifuge__protocol-internal/src/adapters/README.md) | S990 | tf |
| [src/admin/README.md](../centrifuge__protocol-internal/src/admin/README.md) | S991–S992 | tf |
| [src/bridge/README.md](../centrifuge__protocol-internal/src/bridge/README.md) | S993 | tf |
| [src/core/README.md](../centrifuge__protocol-internal/src/core/README.md) | S994–S997 | tf |
| [src/hooks/README.md](../centrifuge__protocol-internal/src/hooks/README.md) | S998 | tf |
| [src/managers/spoke/README.md](../centrifuge__protocol-internal/src/managers/spoke/README.md) | S999 | tf |
| [src/token/hooks/README.md](../centrifuge__protocol-internal/src/token/hooks/README.md) | S1000–S1005 | tf |
| [src/valuations/README.md](../centrifuge__protocol-internal/src/valuations/README.md) | S1006 | tf |
| [src/vaults/ARCHITECTURE.md](../centrifuge__protocol-internal/src/vaults/ARCHITECTURE.md) | S1007–S1015 | tf, known |
| [src/vaults/README.md](../centrifuge__protocol-internal/src/vaults/README.md) | S1016–S1019 | tf |
| [src/vaults/SPECIFICATION.md](../centrifuge__protocol-internal/src/vaults/SPECIFICATION.md) | S1020–S1237 | tf, known |
| [test/integration/recon-end-to-end/README.md](../centrifuge__protocol-internal/test/integration/recon-end-to-end/README.md) | S1238–S1246 | tf, known |
| [test/integration/recon-messaging/README.md](../centrifuge__protocol-internal/test/integration/recon-messaging/README.md) | S1247–S1286 | tf, known |
