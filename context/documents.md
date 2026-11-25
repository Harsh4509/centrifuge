# Document map

The [inventory](entries.json) records dimensions, declarations, levels and source locations. The [statement source index](statement-index.md) maps each source to statement identifiers.

## Engagement and platform references

| Document | Contents |
| --- | --- |
| [scope.json](scope.json) | Pinned repository identity, revision and selected file list. |
| [statements.json](statements.json) | Statement quotes, identifiers, source lines and per-dimension levels. |
| [judging-guidelines.md](judging-guidelines.md) | Selected Sherlock judging guidelines, duplication rules and submission mechanics. |
| [severity-set.json](severity-set.json) | Ordered severity identifiers and definitions, with the supplied severity document. |
| [severities.md](severities.md) | Supplied severity definitions with abbreviation and payout-weight metadata. |
| [finding-report-standard.md](finding-report-standard.md) | Platform guidance for the fields of a finding report. |
| [centrifuge__protocol-internal.md](scope-rules/centrifuge__protocol-internal.md) | Sherlock file-list scope rule for centrifuge__protocol-internal. |
| [Centrifuge_vdk_context_docs_final.md](Centrifuge_vdk_context_docs_final.md) | VDK engagement overview, components, environment, trust model, disclosures and build instructions. |
| [SPECIFICATION.md](SPECIFICATION.md) | VDK property tables, guarantees, non-guarantees, deployment assumptions and test references. |
| [centrifuge-protocol-internal__docs-audits-2023-09-Code4rena.md](centrifuge-protocol-internal__docs-audits-2023-09-Code4rena.md) | Code4rena liquidity-pools report with findings, responses and audit analysis. |
| [centrifuge-protocol-internal__docs-audits-out-of-scope-cantina-bug-bounty.md](centrifuge-protocol-internal__docs-audits-out-of-scope-cantina-bug-bounty.md) | Protocol-wide Cantina bounty disclosure list for the deployed v3.3.0 code. |
| [centrifuge-protocol-internal__docs-audits-out-of-scope-README.md](centrifuge-protocol-internal__docs-audits-out-of-scope-README.md) | Repository description of the bounty disclosure-list lifecycle. |
| [centrifuge-protocol-internal__docs-audits-out-of-scope-vdk.md](centrifuge-protocol-internal__docs-audits-out-of-scope-vdk.md) | VDK disclosure list, trust assumptions, exceptions and specific items. |

The supplied [severity document](severities.md) also contains abbreviation and weight metadata.

## Repository sources

Paths below open the original source snapshot. Statements also referencing supplied copies of the three disclosure-list documents appear in the engagement table above.

| Document | Contents |
| --- | --- |
| [src/token/hooks/HookPolicies.sol](../centrifuge__protocol-internal/src/token/hooks/HookPolicies.sol) | HookPolicies.sol source with NatSpec or comments referenced by the statements file. |
| [src/token/hooks/ShareTokenHook.sol](../centrifuge__protocol-internal/src/token/hooks/ShareTokenHook.sol) | ShareTokenHook.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/Vault.sol](../centrifuge__protocol-internal/src/vaults/Vault.sol) | Vault.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/factories/VaultFactory.sol](../centrifuge__protocol-internal/src/vaults/factories/VaultFactory.sol) | VaultFactory.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/hub/FeeRequestManager.sol](../centrifuge__protocol-internal/src/vaults/hub/FeeRequestManager.sol) | FeeRequestManager.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/hub/OrderBook.sol](../centrifuge__protocol-internal/src/vaults/hub/OrderBook.sol) | OrderBook.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/libraries/BucketLib.sol](../centrifuge__protocol-internal/src/vaults/libraries/BucketLib.sol) | BucketLib.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/libraries/RoleCheckLib.sol](../centrifuge__protocol-internal/src/vaults/libraries/RoleCheckLib.sol) | RoleCheckLib.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/libraries/VaultPricingLib.sol](../centrifuge__protocol-internal/src/vaults/libraries/VaultPricingLib.sol) | VaultPricingLib.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/liquidity/BasinLiquidityRoute.sol](../centrifuge__protocol-internal/src/vaults/liquidity/BasinLiquidityRoute.sol) | BasinLiquidityRoute.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/liquidity/VaultLiquidityRoute.sol](../centrifuge__protocol-internal/src/vaults/liquidity/VaultLiquidityRoute.sol) | VaultLiquidityRoute.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/messaging/VaultRequestRouter.sol](../centrifuge__protocol-internal/src/vaults/messaging/VaultRequestRouter.sol) | VaultRequestRouter.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/oracles/SpokeOracle.sol](../centrifuge__protocol-internal/src/vaults/oracles/SpokeOracle.sol) | SpokeOracle.sol source with NatSpec or comments referenced by the statements file. |
| [src/vaults/policies/RequestPolicies.sol](../centrifuge__protocol-internal/src/vaults/policies/RequestPolicies.sol) | RequestPolicies.sol source with NatSpec or comments referenced by the statements file. |
| [.claude/prompts/async-lifecycle-review.md](../centrifuge__protocol-internal/.claude/prompts/async-lifecycle-review.md) | Repository review notes on asynchronous delivery and message lifecycle. |
| [.claude/prompts/integration-boundary-review.md](../centrifuge__protocol-internal/.claude/prompts/integration-boundary-review.md) | Repository review notes on integration identity, authorization and batching context. |
| [.claude/prompts/pool-isolation-review.md](../centrifuge__protocol-internal/.claude/prompts/pool-isolation-review.md) | Repository review notes on pool identity and isolation boundaries. |
| [.claude/prompts/share-custody-review.md](../centrifuge__protocol-internal/.claude/prompts/share-custody-review.md) | Repository review notes on share custody, hooks and transfer paths. |
| [.claude/rules/coding-style.md](../centrifuge__protocol-internal/.claude/rules/coding-style.md) | Repository coding conventions, inheritance and external-call patterns. |
| [.claude/rules/comments.md](../centrifuge__protocol-internal/.claude/rules/comments.md) | Repository conventions for comments and documentation. |
| [.claude/rules/deployment.md](../centrifuge__protocol-internal/.claude/rules/deployment.md) | Repository deployment conventions and operational assumptions. |
| [.claude/rules/formal-verification.md](../centrifuge__protocol-internal/.claude/rules/formal-verification.md) | Repository notes on formal-verification coverage and model assumptions. |
| [CLAUDE.md](../centrifuge__protocol-internal/CLAUDE.md) | Repository development guide, trust conventions and indexer notes. |
| [docs/SPECIFICATION.md](../centrifuge__protocol-internal/docs/SPECIFICATION.md) | Protocol-wide core property tables and documented non-guarantees. |
| [docs/vaults-policies.md](../centrifuge__protocol-internal/docs/vaults-policies.md) | Fund-mechanics and plugin-design reference with policy examples. |
| [env/README.md](../centrifuge__protocol-internal/env/README.md) | Repository environment configuration and path-resolution reference. |
| [env/spell/006_migration_v3.1/README.md](../centrifuge__protocol-internal/env/spell/006_migration_v3.1/README.md) | v3.1 migration spell reference and component wiring. |
| [script/anvil/README.md](../centrifuge__protocol-internal/script/anvil/README.md) | Local deployment and fixture documentation. |
| [script/checks/README.md](../centrifuge__protocol-internal/script/checks/README.md) | Repository check commands and their coverage. |
| [script/checks/fix_imports.md](../centrifuge__protocol-internal/script/checks/fix_imports.md) | Import-normalization tool usage and limitations. |
| [script/deploy/README.md](../centrifuge__protocol-internal/script/deploy/README.md) | Deployment command, commitment, configuration and recovery reference. |
| [script/testnet/README.md](../centrifuge__protocol-internal/script/testnet/README.md) | Testnet pool and environment setup reference. |
| [src/adapters/README.md](../centrifuge__protocol-internal/src/adapters/README.md) | Cross-chain adapter architecture reference. |
| [src/admin/README.md](../centrifuge__protocol-internal/src/admin/README.md) | Root, guardian and administrative-contract architecture reference. |
| [src/bridge/README.md](../centrifuge__protocol-internal/src/bridge/README.md) | TokenBridge architecture and relayer-flow reference. |
| [src/core/README.md](../centrifuge__protocol-internal/src/core/README.md) | Core hub, spoke and messaging architecture reference. |
| [src/hooks/README.md](../centrifuge__protocol-internal/src/hooks/README.md) | Accounting and bridge hook architecture reference. |
| [src/managers/spoke/README.md](../centrifuge__protocol-internal/src/managers/spoke/README.md) | Spoke-manager architecture and permission reference. |
| [src/token/hooks/README.md](../centrifuge__protocol-internal/src/token/hooks/README.md) | Share-token hook roles, presets, exemptions and extension reference. |
| [src/valuations/README.md](../centrifuge__protocol-internal/src/valuations/README.md) | Valuation-contract architecture reference. |
| [src/vaults/ARCHITECTURE.md](../centrifuge__protocol-internal/src/vaults/ARCHITECTURE.md) | VDK architecture diagrams and explanations of settlement, liquidity and deployment. |
| [src/vaults/README.md](../centrifuge__protocol-internal/src/vaults/README.md) | VDK design, plugin interfaces and extension reference. |
| [src/vaults/SPECIFICATION.md](../centrifuge__protocol-internal/src/vaults/SPECIFICATION.md) | Repository VDK behavioral property tables and test references. |
| [test/integration/recon-end-to-end/README.md](../centrifuge__protocol-internal/test/integration/recon-end-to-end/README.md) | End-to-end invariant harness reference and documented assumptions. |
| [test/integration/recon-messaging/README.md](../centrifuge__protocol-internal/test/integration/recon-messaging/README.md) | Messaging invariant harness, replay properties and coverage limitations. |
| [README.md](../centrifuge__protocol-internal/README.md) | Protocol overview, architecture and general development links. |

All PDF reports and their reading copies are listed in the [report catalog](prior-reports.md). The [Code4rena Markdown report](centrifuge-protocol-internal__docs-audits-2023-09-Code4rena.md) is also listed there.
