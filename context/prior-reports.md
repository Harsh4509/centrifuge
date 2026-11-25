# Prior disclosures and reports

Known status is assessed under [judging guidelines, §3.3](judging-guidelines.md#33-known) and the unchanged [engagement statements](statements.json). Report findings, responses and fix status are retained in full. The catalog locates evidence; a report title or historical severity label is not a verdict.

## Engagement disclosure sources

- [VDK overview, §5 Previous Audits and §6 Known Issues, Accepted Risks & Design Decisions](Centrifuge_vdk_context_docs_final.md#5-previous-audits).
- [VDK specification](SPECIFICATION.md), including the `n` rows and their full Notes.
- [VDK disclosure list](../centrifuge__protocol-internal/docs/audits/out-of-scope/vdk.md), including “What stays in scope even when a component misbehaves”.
- [Protocol-wide Cantina disclosure list](../centrifuge__protocol-internal/docs/audits/out-of-scope/cantina-bug-bounty.md).
- [All statement-bearing sources and identifiers](statement-index.md), including source comments and test-harness documentation.

The overview’s §5 contains the six-item B612 “Vaults V2” disclosure and statuses. The referenced `2026-10-B612-Vaults-V2.pdf` is absent from the supplied collection.

## Protocol reports

Filenames are source identifiers; the publication date, reviewed revision and historical scope are inside each report. Topics locate report content and do not define this engagement’s scope. “Markdown” opens the complete reading copy; “PDF” opens the unchanged original. Numbers in locally converted copies count PDF pages, including covers.

| Report | Topics | Markdown | Original |
| --- | --- | --- | --- |
| 2023-09-Code4rena | Share-token permits, restrictions, redemption and claim arithmetic | [Markdown](centrifuge-protocol-internal__docs-audits-2023-09-Code4rena.md) | [Repository original](../centrifuge__protocol-internal/docs/audits/2023-09-Code4rena.md) |
| 2023-09-SRLabs | Liquidity-pools pallets and cross-chain message processing | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2023-09-SRLabs.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2023-09-SRLabs.pdf) |
| 2023-10-Cantina | LiquidityPool, PoolManager, tranche-token restrictions and request handling | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2023-10-Cantina.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2023-10-Cantina.pdf) |
| 2024-08-Spearbit | CentrifugeRouter, TransferProxy, adapters and tranche-token restrictions | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2024-08-Spearbit.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2024-08-Spearbit.pdf) |
| 2025-02-Cantina | ERC7540Vault claims, transfer restrictions and member data | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-02-Cantina.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-02-Cantina.pdf) |
| 2025-03-xmxanuel | Protocol v3 requests, Gateway and accounting | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-03-xmxanuel.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-03-xmxanuel.pdf) |
| 2025-04-Recon | Protocol v3 accounting, vault requests, rounding and invariant analysis | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-04-Recon.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-04-Recon.pdf) |
| 2025-04-burraSec-1 | Gateway refunds, message gas and pause handling | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-04-burraSec-1.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-04-burraSec-1.pdf) |
| 2025-04-burraSec-2 | Gateway reentrancy, underpaid messages and recovery | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-04-burraSec-2.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-04-burraSec-2.pdf) |
| 2025-05-Cantina | AxelarAdapter, BytesLib, request handling and Gateway | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-05-Cantina.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-05-Cantina.pdf) |
| 2025-05-burraSec | Deployer permissions and Hub dependencies | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-05-burraSec.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-05-burraSec.pdf) |
| 2025-07-xmxanuel | Gateway recovery, BalanceSheet, ShareToken and queueing | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-07-xmxanuel.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-07-xmxanuel.pdf) |
| 2025-07-yAudit | Legacy vaults, BalanceSheet snapshots, max views and transfer restrictions | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-07-yAudit.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-07-yAudit.pdf) |
| 2025-08-Cantina | BalanceSheet batching, reentrancy, vault validation and deployment | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-08-Cantina.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-08-Cantina.pdf) |
| 2025-08-burraSec | LayerZeroAdapter funding, message failure and configuration | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-08-burraSec.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-08-burraSec.pdf) |
| 2025-09-burraSec | Subsidy spending, multicalls, adapter votes and message delivery | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-09-burraSec.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-09-burraSec.pdf) |
| 2025-10-burraSec | Pool identity checks, adapter payloads and message gas | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-10-burraSec.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-10-burraSec.pdf) |
| 2025-10-yAudit | NAV accounting, SyncManager conversions and transfer hooks | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-10-yAudit.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-10-yAudit.pdf) |
| 2025-12-Sherlock-Blackthorn | Pool isolation, globalEscrow, price accounting and message batching | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-12-Sherlock-Blackthorn.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-12-Sherlock-Blackthorn.pdf) |
| 2025-12-xmxanuel | BalanceSheet reentrancy, batching and governance permissions | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2025-12-xmxanuel.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2025-12-xmxanuel.pdf) |
| 2026-01-yAudit | Escrow storage, deployment salts, subsidy events and documentation | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-01-yAudit.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-01-yAudit.pdf) |
| 2026-02-Sherlock-deployment | Protocol contract deployment check and verification | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-02-Sherlock-deployment.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-02-Sherlock-deployment.pdf) |
| 2026-03-xmxanuel-onchain-pm | OnchainPM, Weiroll scripts and circuit-breaker/slippage guards | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-03-xmxanuel-onchain-pm.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-03-xmxanuel-onchain-pm.pdf) |
| 2026-04-Sherlock-onchain-pm | SlippageGuard and CircuitBreakerGuard | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-04-Sherlock-onchain-pm.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-04-Sherlock-onchain-pm.pdf) |
| 2026-04-burraSec-onchain-pm | OnOffRamp, OnchainPM, SlippageGuard and script state | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-04-burraSec-onchain-pm.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-04-burraSec-onchain-pm.pdf) |
| 2026-06-yAudit-v3.3 | StdManifest, NAV and oracle updates, authorization and bridge rate limits | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-06-yAudit-v3.3.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-06-yAudit-v3.3.pdf) |
| 2026-07-burraSec-bridge | TokenBridge relayer funding, refunds and share custody | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-07-burraSec-bridge.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-07-burraSec-bridge.pdf) |
| 2026-07-burraSec-v3.3 | Pool policies, adapter sessions, accounting sync and price updates | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-07-burraSec-v3.3.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-07-burraSec-v3.3.pdf) |
| 2026-08-FV | Core hub, spoke and messaging verification properties and assumptions | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-08-FV.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-08-FV.pdf) |
| 2026-08-Sherlock | Share-token identity, frozen claims, Supervisor and sync-vault views | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-08-Sherlock.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-08-Sherlock.pdf) |
| 2026-08-burraSec-ShareManager | ShareManager revocation, freezing, approval and events | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-08-burraSec-ShareManager.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-08-burraSec-ShareManager.pdf) |
| 2026-08-burraSec-v3.3 | Linked asset/liability repricing, vault registration and NAV initialization | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-08-burraSec-v3.3.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-08-burraSec-v3.3.pdf) |
| 2026-09-FV | Core hub, spoke and messaging verification properties and assumptions | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-09-FV.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-09-FV.pdf) |
| 2026-09-Sherlock | Price timestamps and SimplePriceManager issuance overflow | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-09-Sherlock.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-09-Sherlock.pdf) |
| 2026-09-burraSec | OpsGuardian and permissionless asset registration | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-09-burraSec.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-09-burraSec.pdf) |
| 2026-Alex-Filippov | Adapter deduplication, escrow reservations, controller requests and gas | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-Alex-Filippov.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-Alex-Filippov.pdf) |
| 2026-LonelySloth | MultiAdapter negative-vote reset and message execution | [Markdown](derived/centrifuge__protocol-internal/docs/audits/2026-LonelySloth.md) | [PDF](../centrifuge__protocol-internal/docs/audits/2026-LonelySloth.pdf) |

## Bundled Safe dependency reports

These files accompany the Safe dependency in the repository. Their own scope, assumptions and versions are recorded in each report.

| Report | Topics | Markdown | Original |
| --- | --- | --- | --- |
| Gnosis_Safe_Audit_Report | Gnosis Safe contracts review | [Markdown](derived/centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report.md) | [PDF](../centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report.pdf) |
| Gnosis_Safe_Audit_Report_1_1_0 | Safe 1 1 0 review | [Markdown](derived/centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_1_0.md) | [PDF](../centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_1_0.pdf) |
| Gnosis_Safe_Audit_Report_1_1_1 | Safe 1 1 1 review | [Markdown](derived/centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_1_1.md) | [PDF](../centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_1_1.pdf) |
| Gnosis_Safe_Audit_Report_1_2_0 | Safe 1 2 0 review | [Markdown](derived/centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_2_0.md) | [PDF](../centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_2_0.pdf) |
| Gnosis_Safe_Audit_Report_1_3_0_Final | Safe 1 3 0 Final review | [Markdown](derived/centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_3_0_Final.md) | [PDF](../centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_3_0_Final.pdf) |
| Gnosis_Safe_Audit_Report_1_3_0_Initial | Safe 1 3 0 Initial review | [Markdown](derived/centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_3_0_Initial.md) | [PDF](../centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_3_0_Initial.pdf) |
| Gnosis_Safe_Formal_Verification_Report_1_0_0 | Gnosis Safe proof model and findings | [Markdown](derived/centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Formal_Verification_Report_1_0_0.md) | [PDF](../centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Formal_Verification_Report_1_0_0.pdf) |
| Gnosis_Safe_Symbolic_Execution | Gnosis Safe verification worksheets | [Markdown](derived/centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Symbolic_Execution.md) | [PDF](../centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Symbolic_Execution.pdf) |
| Safe_Audit_Report_1_4_0 | Safe 1 4 0 review | [Markdown](derived/centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Safe_Audit_Report_1_4_0.md) | [PDF](../centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Safe_Audit_Report_1_4_0.pdf) |

## Format reference

Supplied parser Markdown retains its original image references; the corresponding image files were not supplied. The PDFs retain those visuals. Locally converted verification reports include scene-diagram images beside the page text. The Safe symbolic-execution PDF contains oversized worksheets; its original preserves cell geometry and branch colors.
