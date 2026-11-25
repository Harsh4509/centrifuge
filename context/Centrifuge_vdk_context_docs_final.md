# Vault Development Kit: audit docs

Protocol docs for the Sherlock Audit Engine engagement on the Vault Development Kit (VDK).

Scope is `src/vaults/**` except `src/vaults/VaultRouter.sol`, and the share token hook: `src/token/hooks/**` (`ShareTokenHook`, `HookPolicies` and their interfaces) with the hook interfaces it implements, `src/token/interfaces/IRoleHook.sol` and `ITransferHook.sol`. Everything else is out of scope and trusted to work as documented, including `VaultRouter`, `StdHubPolicy`, the accounting managers (`NAVManager`, `SimplePriceManager`), the libraries in `src/misc`, `GasService`, `src/core`, `src/deployment` and the deployment scripts. This doc still describes the out-of-scope parts where the in-scope code depends on them.

This file is the entry point for researchers. It is deliberately short on detail that lives elsewhere and links there instead. The specification and the out-of-scope lists are normative. `vaults-policies.md`, the architecture diagrams and design notes are not: their accuracy is out of scope ([`vdk.md`, "Off-chain and operational dependencies"](https://github.com/centrifuge/protocol/blob/vdk/docs/audits/out-of-scope/vdk.md#off-chain-and-operational-dependencies)).

| Document | What it is |
|---|---|
| [`src/vaults/README.md`](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/README.md) | What the kit is, the plugin slots, how to write a plugin |
| [`src/vaults/ARCHITECTURE.md`](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/ARCHITECTURE.md) | How it works, with diagrams: settlement, horizon, escrow reservations, instant lane, deployment |
| [`src/vaults/SPECIFICATION.md`](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/SPECIFICATION.md) | Over 300 properties, one row each, with the tests behind them. Rows marked `n` are documented non-guarantees |
| [`docs/audits/out-of-scope/vdk.md`](https://github.com/centrifuge/protocol/blob/vdk/docs/audits/out-of-scope/vdk.md) | The VDK out-of-scope list, extending [`cantina-bug-bounty.md`](https://github.com/centrifuge/protocol/blob/vdk/docs/audits/out-of-scope/cantina-bug-bounty.md) |
| [`docs/vaults-policies.md`](https://github.com/centrifuge/protocol/blob/vdk/docs/vaults-policies.md) | Real fund mechanics evaluated against the plugin surface |
| [Developer docs](https://docs.centrifuge.io/developer/vault-development-kit/overview/) | Public preview of the kit |

## 1. Protocol Overview

### 1.1 Summary

Centrifuge is a protocol for tokenizing real-world assets. A **pool** is managed on one **hub** chain, where the balance sheet, the double-entry accounting, the NAV and the share prices live. The pool is distributed on any number of **spoke** chains, where investors hold the pool's share tokens and enter and exit through vaults. Hub and spokes talk over a cross-chain messaging layer (the gateway, verified by more than one messaging provider). A pool whose hub and spoke share a chain uses the same contracts, with messages delivered locally.

The VDK is the vault layer on the spoke. Each `Vault` is immutable and serves one `(pool, share class, asset)` position. A position can have several vaults, told apart by their `variant` and plugins. It implements ERC-4626, ERC-7540 (asynchronous requests), ERC-7575 (multi-asset shares) and ERC-8161 (transferable pending requests). It has two lanes:

- **Async lane (ERC-7540).** `requestDeposit` and `requestRedeem` put the assets or shares in the pool's escrow and register a request. The request joins a **bucket**, the unit the hub sees as one order. The pool's hub manager fills or cancels the order, possibly in part and at a price it supplies, and each investor's pro-rata slice of the fill is credited to their **claimable ledger** and then claimed with `deposit`/`mint` or `withdraw`/`redeem`.
- **Instant lane (ERC-4626).** With an instant policy set, the 2-argument `deposit`, `mint`, `withdraw` and `redeem`, and the owner's 3-argument `withdraw` and `redeem`, execute at the oracle's prices on the spoke, up to a capacity the policy reports, when the controller has nothing claimable and nothing pending on that side. A redemption larger than the escrow can pay draws the shortfall from a **liquidity route**.

The product-specific behavior lives in six narrow plugin contracts: five slots on the vault, fixed at construction, plus the share token's role hook, which the vault reads from the token on every action and the pool can swap. A tokenized treasury, a private credit fund, a staking token and a fund of funds are the same bytecode with different plugins.

Lineage: the vault is a dual-mode ERC-7540 vault in the family of Centrifuge's v1 `AsyncVault` and `SyncDepositVault`. It replaces them with one contract. The vault does not hold funds itself: assets and parked shares sit in the pool's `Escrow` (from `src/core`), and the vault asks the spoke to reserve and move them. Share price is a valuation from hub-notified prices, never a ratio of balances ([SPECIFICATION](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/SPECIFICATION.md), "Share price is a valuation, never a ratio of balances").

The vault, its plugin slots and the contracts it talks to ([`contract-map.svg`](https://github.com/centrifuge/protocol/blob/vdk/docs/architecture/vaults/contract-map.svg)):

![The vault, its five plugin slots and the contracts it talks to on the spoke and hub chains](https://raw.githubusercontent.com/centrifuge/protocol/vdk/docs/architecture/vaults/contract-map.svg)

### 1.2 Key Design Changes / Novel Mechanisms

The reference model is ERC-7540 with the v1 Centrifuge vaults. What is new, and where bugs are most likely:

- **Buckets, contributions and a fold horizon.** ERC-7540 claims are per controller, but a shared window bucket has an unbounded number of contributors. Settlement is therefore recorded once on the bucket (O(1) for the hub callback), and each contributor's floor pro-rata slice is **folded** into their claimable ledger later, either at settlement (an unbatched bucket has one owner), by their own next claim (the **horizon**, their latest `foldHorizon` positions), or by anyone through `foldRequest`. Views net the horizon's settled-but-unfolded slices so a fold is not observable as a balance jump. See [ARCHITECTURE, "How a request settles"](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/ARCHITECTURE.md#how-a-request-settles) and ["Horizon rules"](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/ARCHITECTURE.md#horizon-rules).
- **Plugins fixed at construction, no upgrades.** The five slots are constructor immutables. There is no setter and no proxy. A change ships as a new vault under a new `variant`, issuing the same share token.
- **The vault allocates ids, the policy names keys.** A request policy answers a bucket **key**. The vault keeps one bucket per `(key, side)` and allocates the `localId` from its own counter, so a policy cannot invent or collide ids. The request id is `(vault address << 96) | localId`, so parallel vaults on one position never collide and no registry is needed.
- **One lane per call, decided by the controller's own state.** The 2-argument `deposit`/`mint`/`withdraw`/`redeem`, and the owner's 3-argument `withdraw`/`redeem` (which share their selectors with ERC-4626), trade instantly only for a controller with nothing claimable and nothing pending on that side, and claim otherwise, never a mixture. The 3-argument `deposit`/`mint` are claims only, so a retried claim never becomes a purchase, and an operator's 3-argument `withdraw`/`redeem` only claim.
- **Settlement is one hub message per fill, applied as legs.** `OrderBook` sends one `SettledDeposit`, `SettledRedeem` or cancellation message per fill. `VaultRequestRouter` applies it to the vault as typed calls in one transaction (`approveDeposits`, `issueShares`, `fulfillDepositRequest`, or `revokeShares`, `fulfillRedeemRequest`), so legs cannot land partially.
- **Cancellation is the manager's, at order level.** There is no investor cancel. A cancellation carries a gross and a net amount, and the cancelled amount is claimed on the opposite side (cancelled deposit assets through `withdraw`, cancelled redeem shares through `mint`).
- **Role checks on every vault action.** The vault asks the share token's hook (`IRoleHook.onRoles`) a set of role checks per action (`Entry`, `Exit`, `Payout`, `Refund`), built by `RoleCheckLib`, because the vault's share legs use an authorized transfer, which reaches the hook's `onERC20AuthTransfer` but which the shipped hooks do not restrict.
- **Escrow reservations.** Every asset in the escrow is reserved for a request, in the holding (counted in NAV), or earmarked for a redemption payout. Reservations are keyed by reason, per request for deposits and one shared reason for redemptions.
- **Liquidity routes.** An instant redemption larger than the escrow draws the shortfall from an `ILiquidityRoute`, in the same transaction. `BasinLiquidityRoute` books the draw as a liability on the pool's balance sheet. `VaultLiquidityRoute` redeems positions in underlying vaults for a fund of funds, recursively.
- **Singletons shared by all pools.** The policies, oracle, `VaultLiquidityRoute`, routers, factory, `OrderBook` and `FeeRequestManager` are per-network singletons, and a `BasinLiquidityRoute` is one per venue, shared by every pool that draws on it. A vault is per position. "Which pool is this call for" is therefore a security boundary, enforced by the registry and not by caller-supplied addresses ([SPECIFICATION, "Deployment model"](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/SPECIFICATION.md#deployment-model)).
- **Size.** `Vault` is about 49 kB of runtime code (`forge build --sizes` has the current figure), above EIP-170, so it deploys only on chains with a raised contract size limit.

### 1.3 Actors

- **Investor / controller.** Holds the pool's share token and enters and exits through the vault. Goal: subscribe and redeem at fair prices, claim what settles. An **operator** acts for a controller (ERC-7540). The **owner** is who funds a request.
- **Sponsor.** A payer the vault's instant policy accepts (a per-vault list the pool sets, empty by default). It may fund a position for a controller it does not act for, without any say over its claims. Goal: fund positions for the controllers it serves.
- **Pool manager (hub).** Runs the pool: fills and cancels orders at prices and fees it chooses, sets plugin terms, admits and freezes investors, links vaults. Goal: operate the product.
- **Spoke manager.** Moves pool assets through the balance sheet on one chain. Every VDK vault is a spoke manager of its pool (the spoke calls it makes on requests, instant trades, settlements and claims all need the role). Goal: keep the pool's holdings on that chain where the pool wants them.
- **Sentinel.** Can cancel a pending, time-locked authorization of a pool manager. Goal: stop a bad authorization before it takes effect.
- **Keeper.** Anyone who calls the permissionless `flushRequest` (send a closed bucket), `foldRequest` (fold a position outside a horizon), `VaultRouter.claimDeposit`/`claimRedeem` for a controller that made the router its operator, and the gateway `retry`. No role is needed. Goal: keep windows sent and claims reachable, for gas only.
- **Liquidity venue and its provider.** The third party behind a `BasinLiquidityRoute` (sets a credit line per vault) or the underlying vault behind a `VaultLiquidityRoute`. Goal: earn on liquidity lent to the routing vaults.
- **Integrator.** A wallet, aggregator or protocol that talks to the vault through ERC-4626, ERC-7540 or `VaultRouter`. Goal: enter and exit through the standard interfaces.
- **Root / protocol governance.** The only ward of a deployed vault, used for `recoverTokens`. Granting Root ward access is timelocked (48 hours on mainnet). Goal: keep the protocol safe and wired.

### 1.4 Core User Flows

- **Async deposit.** Entry point `Vault.requestDeposit(assets, controller, owner)`. Touches: Vault, instant policy (`canCredit`, when the caller does not act for the controller), role hook (`Entry`), request policy (`onRequest`), Spoke and Escrow (note and reserve the assets), then `VaultRequestRouter` to `OrderBook` on the hub when the bucket is flushed. Later `OrderBook` fill, `VaultRequestRouter` callbacks, Vault settlement, then the claim `Vault.deposit(assets, receiver, controller)` or `mint`. Asynchronous.
- **Async redeem.** Entry point `Vault.requestRedeem(shares, controller, owner)`. Mirror image: shares are parked in the escrow, the fill revokes (burns) them and earmarks the payout, and the claim is `Vault.redeem` or `withdraw` (`Payout` role check).
- **Instant deposit or redeem.** Entry point `Vault.deposit(assets, receiver)`, `mint`, `withdraw`, `redeem` (2-argument, controller is the caller), and the owner's 3-argument `withdraw`/`redeem`, while the controller has nothing claimable or pending on that side. Touches: Vault, oracle (`prices`), instant policy (capacity and fee), role hook, Escrow, and for a shortfall the liquidity route. Synchronous, one transaction.
- **Claim.** Entry point `Vault.deposit/mint/withdraw/redeem` while the controller has something claimable or pending on that side, the 3-argument `deposit`/`mint`, or an operator's 3-argument `withdraw`/`redeem`. Touches: Vault (folds the controller's horizon), role hook, Spoke and Escrow (pays out the reserved assets or the escrowed shares). Synchronous.
- **Fold and flush (keepers).** `Vault.foldRequest(localId, controller)` and `Vault.flushRequest(localId)`. Touches: Vault, and for a flush `VaultRequestRouter`, then the gateway. Synchronous on the spoke.
- **Deploy and link a vault.** `VaultFactory.deploy` on the spoke, then the hub's `updateVault(DeployAndLink)`, `UpdateManager`, and optionally `SetVault`. Touches: VaultFactory, then Hub, the hub policy and a message to the spoke's `SpokeHandler`, which checks the vault's own `poolId` and `scId`, and `SpokeRegistry`. Asynchronous across chains.
- **Configure a plugin.** Hub manager calls `Hub.managerCall(poolId, centrifugeId, target, payload, ...)`, a message carries it to the spoke (a direct call when the target is on the hub's chain), and the Envoy calls `target.fromHub(poolId, payload)`. Touches: Hub, the hub policy, the messaging layer, Envoy, target. Asynchronous across chains.
- **Transfer a pending request.** `Vault.transferDepositRequest` / `transferRedeemRequest` (ERC-8161), where the request policy supports it. Touches: Vault (folds the position), role hook. Synchronous.
- **Investor entrypoint (out of scope).** `VaultRouter.multicall` bundles approvals, requests, claims and cross-chain share transfers. Touches: VaultRouter, the vaults it names, and the Spoke for a cross-chain share transfer. Synchronous on the spoke.

How a bucket becomes claimable shares, and the arithmetic: a contributor's slice is `fill x contribution / total`, floored. Dust stays in the escrow. A later fill of the same bucket adds the difference to each contributor's snapshot.

![Requests pool into a bucket that the hub fills; a fold credits a cell to its investor's ledger, and a claim folds only an investor's horizon](https://raw.githubusercontent.com/centrifuge/protocol/vdk/docs/architecture/vaults/request-settlement.svg)

Which entrypoint an instant call takes is decided once, by the controller's own state:

![Which path a call takes, and who receives what in an instant deposit and an instant redeem](https://raw.githubusercontent.com/centrifuge/protocol/vdk/docs/architecture/vaults/instant-lane.svg)

The three states of an asset in the escrow:

![The three states of an asset in the escrow, the calls that move it between them, and a worked example in numbers](https://raw.githubusercontent.com/centrifuge/protocol/vdk/docs/architecture/vaults/escrow-reservations.svg)

## 2. Detailed Breakdown by Component

Ordered from the most central (where funds and accounting live) to the most peripheral. Property-level detail is in the [SPECIFICATION](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/SPECIFICATION.md) section for each contract.

### 2.1 Vault (`src/vaults/Vault.sol`)

**Purpose.** One flat contract holding all investment state and both flows. It holds no funds at rest: assets and parked shares live in the pool `Escrow`, reservations are made through the Spoke, and the vault's own token touches are transient. State is the per-controller claimable ledger (`_investments`), the buckets, contributions and per-controller sides (`_buckets`), the horizon's overflow (`_horizon`), operators, and the key-to-bucket maps (`keyOf`, `_bucketIds`). All configuration (identity, `spoke`, `spokeRegistry`, `escrow`, the five `VaultPlugins` slots, the fold horizon) is constructor-fixed. The only ward is Root (for `recoverTokens`). The investor entrypoints are `nonReentrant`, with a strict lock. The request manager's callbacks (`approveDeposits`, `issueShares`, `fulfill*`, `cancel*`, `revokeShares`) are not locked, by design: a same-chain request manager settles inside a locked flush.

**Lineage & changes.**
- Replaces the v1 `AsyncVault`, `SyncDepositVault` and the old `VaultRouter`. Request ids, ledger and settlement are redesigned (buckets, folding), investor-initiated cancellations are removed, and instant trading is added to the same contract. The list of removed and changed behavior is in [ARCHITECTURE, "Coming from the v1 vaults"](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/ARCHITECTURE.md#coming-from-the-v1-vaults).
- Conformance with ERC-4626, ERC-7540, ERC-7575, ERC-8161 and ERC-165 apart from the listed deviations, among them previews and `max*` on a dual-mode vault and no allowance flow on `withdraw`/`redeem` ([SPECIFICATION, "ERC-7540 / ERC-4626 conformance"](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/SPECIFICATION.md#erc-7540--erc-4626-conformance)).

**Mechanics & math.**
- *Ledger and price.* A controller's claimable is `InvestmentState`: `depositShares`/`depositAssets` (claimable by `deposit`/`mint`), `redeemAssets`/`redeemShares`, and `refundShares`/`refundAssets` (cancellations, claimed on the opposite side and taken first). A fold adds the contribution's newly settled assets and shares to the ledger, and claims convert pro-rata over the ledger's totals, so a claim pays the weighted average of the fills it holds, not the current price.
- *Pro-rata slice.* `slice = floor(settled x contribution / total)` per leg, tracked as snapshots (`foldedAssets`, `foldedShares`, `foldedCancelled*`, `foldedSettlements`) so later partial fills only add the difference. Dust stays in the escrow.
- *Horizon.* Per controller and side, the latest `foldHorizon` positions (at least the request policy's `maxOpenBuckets`, default that value, no upper bound). A position the controller did not submit or fund (a sponsor's, or one transferred to it) never takes a slot kept for their open buckets. An evicted unsettled position still counts as pending.
- *Pricing.* Every instant conversion, instant-mode preview and `convertTo*` goes through `VaultPricingLib` and the oracle's `prices`, which returns the pair and a validity verdict in one read. Async claims convert from the stored ledger and read no price. `totalAssets()` is `convertToAssets(totalSupply())`, a valuation, so donations move no price or capacity.
- *Reservations.* A deposit reserves its assets under a per-request reason. A redeem fill reserves the payout under the shared redeem reason before the burn. A deposit cancellation releases the gross from the request's reservation and earmarks the net under the shared redeem reason. A claim pays out with `withdrawReserved`.

**Expected inputs & caller responsibilities.**
- Integrators are expected to read `claimableMint`/`claimableWithdraw` and `maxMint`/`maxWithdraw` for what a controller can claim. The `requestId` argument of ERC-7540 `claimable*Request` is ignored, as ERC-7540 allows. `pending*Request` reads the controller's total for request id 0 and that bucket's pending amount for any other id.
- A retried 3-argument `redeem`/`withdraw` by the owner takes the instant lane when nothing is claimable or pending on that side, as the selectors are shared with ERC-4626. Integrators retrying a claim should not assume it reverts.
- Slippage is the caller's: instant calls execute at the oracle's price. A pool that wants a bound quotes a spread. Callers needing a minimum output check `preview*` or bound the call themselves.
- Value is assumed to be a plain ERC-20 asset (`tokenId` zero).

**Edge cases & intentional behavior.**
- A pending or claimable position, even one a sponsor funded, holds the controller's instant lane in async on that side until it is claimed.
- A fold whose credit would push a `uint128` ledger counter past its maximum is deferred, not saturated, and the position stays pending (see 6.1).
- `PerInvestorPolicy` reuses the request id once a bucket settles.
- Refund claims emit `Withdraw`/`Deposit` with zero shares or assets, and `maxDeposit`/`maxRedeem` read zero for refunds (claim with `mint`/`withdraw`).
- `claimableDepositRequest`/`claimableRedeemRequest` are per controller, not per request id.

**Areas of concern.** These are the areas the team most wants reviewed. Listing an area here does not make a finding in it known or accepted.
- The fold and horizon accounting (`BucketLib`, `HorizonLib`): pro-rata rounding, `settlements` and `foldedSettlements` bookkeeping, eviction, transfer of a partly settled position, and the deferred-fold path.
- Reservation arithmetic across `approveDeposits`, `revokeShares`, cancellations and instant trades, in particular over-reservation (`reserved` above `total`, [SPECIFICATION](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/SPECIFICATION.md) row "Parallel vaults on one position cannot together reserve more than the escrow holds").
- The instant-or-claim routing and its interaction with positions credited by third parties.
- Role-check ordering: checks run before the vault changes state, with figures matching what the vault does (`RoleCheckLib`).

### 2.2 Settlement libraries (`BucketLib`, `HorizonLib`, `VaultPricingLib`)

**Purpose.** Pure accounting, isolated from the vault so it is fuzzed independently (`BucketLibInvariants`, `VaultPricingLibInvariants`). `BucketLib` owns the bucket, contribution and per-controller `Side` state: contribute, flush, settle, fold, transfer, and the per-side pending totals. `HorizonLib` owns the per-controller horizon (two inline entries kept in `BucketLib`'s `Side`, plus an overflow mapping) and the `unfolded` view netting. `VaultPricingLib` owns the price conversions; the pro-rata claim arithmetic is in the vault's `_claim*`.

**Mechanics.** See 2.1. `settle` enforces what a locally registered request manager must not break: it rejects a spent bucket or the wrong side (`NoPendingRequest`), an unflushed bucket (`BucketNotFlushed`), a settlement beyond what the bucket sent (`OverSettled`), and a non-zero leg against a zero one (`OneSidedFill`). These bind the ledger legs (`fulfill*`, `cancel*`). `approveDeposits`, `issueShares` and `revokeShares` take no bucket, so a request manager the pool registers itself can call them apart from a fill (6.1).

**Edge cases.** `settle` accumulates and is not idempotent: it rejects a duplicate only when the bucket is spent or the duplicate exceeds what the bucket sent. Exactly-once delivery is inherited from the core messaging layer, not enforced here ([SPECIFICATION](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/SPECIFICATION.md), `n` row).

**Areas of concern.** These are the areas the team most wants reviewed. Listing an area here does not make a finding in it known or accepted. Rounding direction at every conversion (all in the vault's favor), the `uint128` bounds of the ledger counters, `uint64` local id width, and share price near the D18 minimum.

### 2.3 Request policies (`src/vaults/policies/RequestPolicies.sol`)

**Purpose.** Decide who may request and which bucket a request joins. `onRequest(vault, controller, owner, isDeposit, amount)` returns a **key**; the vault maps it to a bucket. A zero key opens a fresh bucket every time. `isBatched`, `maxOpenBuckets` and `supportsTransfers` are read once, at construction. `isClosed(vault, key)` is asked on a flush and when a request opens a new batch. The shipped policies keep no state and take no configuration after construction.

| Policy | Key | Batched | Transfers | Use |
|---|---|---|---|---|
| `PerInvestorPolicy` | the controller | no | no | one hub position per controller and side, extended by repeat requests |
| `PerRequestPolicy` | zero | no | constructor flag | a fresh bucket per request, individually priced and tradeable |
| `PerPeriodPolicy(window, offset, depositNotice, redeemNotice)` | the window index (shifted by the side's notice) | yes | yes | dealing windows: one hub message per window and side |

**Expected inputs.** A non-batching policy's key must be the controller's alone (derived from it), since an unbatched bucket has one owner. A batching policy may not answer the zero key (`ZeroBatchKey`). `IRequestPolicy.onRequest` is not `view`, so a third-party policy may record state.

**Edge cases.** A window cannot be flushed while open. A request after a window closed lands in the next window. The next window's first request on a side flushes the previous closed batch, unless a keeper already did. `PerPeriodPolicy` with `offset` ahead of the chain clock panics until the clock passes it ([SPECIFICATION](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/SPECIFICATION.md), `n` row). A policy can block a request by reverting, by design.

### 2.4 Instant policy (`ReserveInstantPolicy`)

**Purpose.** Capacity, fees, caller allowlists and sponsors for the instant lane. Per-vault `Config`: `feeRecipient`, `depositFeeBps`, `redeemFeeBps` (each strictly below 10,000), `redeemEnabled`, `gatedDeposit`, `gatedRedeem`, `maxReserve`. Configuration is Envoy-only and bound to the vault's own pool from the registry.

**Mechanics.** Deposit capacity is `saturatingSub(maxReserve, spoke.availableBalanceOf(...))`, the escrow's available balance; `maxReserve == 0` closes instant deposits. Redeem capacity is the escrow's available balance plus what the route supplies, less what the escrow has reserved beyond its total, read live, so the whole liquid position can leave in one transaction (intended: the escrow balance is the pool's statement of instant liquidity). Fees are basis points of the **gross**, rounded up. With a recipient the fee is paid to it, with none it stays in the escrow and backs no shares, accruing to the remaining holders. A negative fee is a rebate paid by the recipient (`ReserveInstantPolicy` never rebates). Quotes equal execution for any policy that does not rebate and quotes the same for any receiver.

**Expected inputs.** An instant lane needs a price-freshness bound: the canonical oracle's `maxAge` of 1 day, or a pool's own oracle deployed with a `maxAge` and, for a pool that quotes a tight spread, a tighter `maxSkew`. A pool that wants both a manager fee and a holder spread names a splitter as recipient ([ARCHITECTURE, "Where an instant fee goes"](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/ARCHITECTURE.md#where-an-instant-fee-goes)).

**Edge cases.** Deposit capacity ignores the receiver (global per vault). Allowlists key on the caller, never the receiver, so through `VaultRouter` the allowlist names the router.

### 2.5 Oracle (`SpokeOracle`)

**Purpose.** The prices every conversion uses, and whether the instant lane may trade on them. Reads hub-notified prices from the spoke registry. `prices(poolId, scId, assetId)` returns the asset price, the share price and one validity verdict. Valid means: set at least once, not paused, `computedAt` within `maxAge` (and not in the future) when `maxAge != 0`, and the two prices' hub computation times (`computedAt`) within `maxSkew` of each other when `maxSkew != 0`. A pool pause can be set from the hub, which is immediate only on the hub's own chain (to another chain it waits out the hub policy's delay), or by a pauser the pool names from the hub, who pauses on the spoke's chain at once. Only the hub unpauses.

**Mechanics.** The instant executes and the previews of a caller in instant mode require the verdict. On an invalid verdict, capacity views report zero rather than revert (but see 6.1 on extreme price ratios). Async settlement and claims ignore the verdict, since they price from the stored ledger. The oracle never acts on an invalid price: it states the verdict and the caller decides.

**Edge cases.** The canonical oracle is shared by all pools, deployed with `maxAge` of 1 day and `maxSkew` equal to `maxAge`. Price magnitude is unbounded here, bounding belongs to hub-side policy ([SPECIFICATION](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/SPECIFICATION.md), `n` row).

### 2.6 Liquidity routes (`BasinLiquidityRoute`, `VaultLiquidityRoute`)

**Purpose.** Where instant redemption liquidity comes from when the escrow is short (`provide`), and where fresh deposits go (`forward`, which both shipped routes leave empty). A route is all-or-nothing: a draw that cannot be met reverts.

- `BasinLiquidityRoute`: one per venue, shared by every pool that draws on it. It keys a credit line and a receivable by the drawing vault. A draw must fit under the lower of a limit the pool sets through the Envoy and a credit the venue's liquidity provider sets, checked only when the vault draws. A draw is a loan: the route mints liability `AccountingToken`s for the principal and deposits them into the pool's escrow, so once the pool has initialized the liability holding on the hub, NAV per share is unchanged by a draw and by its repayment (until then NAV overstates, see 6.1). The setup a pool needs before a first draw is in [ARCHITECTURE, "Basin debt on the balance sheet"](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/ARCHITECTURE.md#basin-debt-on-the-balance-sheet).
- `VaultLiquidityRoute`: a fund of funds releases its positions in underlying vaults on demand through each underlying's own instant exit. Capacity is the lower of `previewRedeem(held)` and `withdrawCapacity` per underlying, net of its exit fee, each read as a plain `staticcall` capped at `QUOTE_GAS` (400,000), up to four reads per underlying, so an underlying that cannot quote reads as zero. The underlying's pool consents to each routing vault by name. Linkage and consent are checked when the routes are set and again on every use. A draw reverts when the underlying hands back more shares than the draw released (`ExcessShares`) or leaves the route holding fewer than before the draw (`ExcessSharesTaken`).

**Areas of concern.** These are the areas the team most wants reviewed. Listing an area here does not make a finding in it known or accepted. Venue liquidity is not partitioned per vault: lines that together exceed the venue's liquidity are each quoted against the whole of it. Over-reservation clears on the first draw. Recursion depth through nested routes. Rounding and dust return of shares to the pool.

### 2.7 Share token role hook (`src/token/hooks`, `IRoleHook`)

**Purpose.** Who may hold, leave or be paid. The vault asks the hook once per action, `onRoles(token, checks)`, where each check is `(role, from, to, assets, shares, effect)` and `effect` says what the check does to a position (`Grows`, `Neutral`, `Shrinks`, `Moves`). `RoleCheckLib` builds the checks from each action (a `VaultAction`, typed in `IAsyncVault.sol`) ([ARCHITECTURE, "Share token restrictions"](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/ARCHITECTURE.md#share-token-restrictions) has the table). The shipped hook is `ShareTokenHook`, deployed once per `HookPolicies` preset: `freezeOnly`, `redemptionRestrictions`, `freelyTransferable` and `fullRestrictions`. A hook without the `IRoleHook` surface fails closed.

**Mechanics.** Figures are the vault's exact figure where it has one and the other unit at the current price. While the price is not vouched for the estimate is `type(uint128).max`, so a limit refuses rather than passes. `ShareTokenHook` ignores the figures and the effect; they exist for custom hooks that limit positions. An exit limit therefore reads `shares`, never `assets`. A hook that limits a position counts a vault action once, on its role check, and limits only `Transfer` movements on the transfer callback.

**Edge cases.** The escrow of every pool is treated as a member of every class in every role. A hook can be swapped by the pool (per share class), and blocks claims if it refuses.

### 2.8 Request transport (`VaultRequestRouter`, `RequestMessageLib`, `RequestCallbackMessageLib`)

**Purpose.** The only contract in `src/vaults` that speaks the request wire. Outbound, it derives the request id from `msg.sender` and the position from the caller's vault details, so a vault can only emit its own id. Inbound, it resolves the target vault from the request id, checks the callback's `(pool, share class, asset)` against the registry record, and applies the callback as a typed call. It is the pool's registered spoke request manager and a singleton, so the vault's `onlyRequestManager` check says nothing about which pool authorized a settlement, and the registry check is the binding.

**Edge cases.** No per-request state (it keeps only a per-pool `extraGasLimit`). No reentrancy guard around its typed calls. Callbacks to an unlinked vault revert: across chains the message stays in the gateway, retryable, while on a same-chain hub the manager's fill itself reverts. It takes a subsidy from the pool only when the send is cross-chain and not already in a batch. The router never accumulates ETH, but `receive()` is unguarded.

### 2.9 Hub request managers (`OrderBook`, `FeeRequestManager`)

**Purpose.** `OrderBook` is the minimal hub-side request manager: one independent order per request id, auto-approved on receipt, filled or cancelled by the pool's manager with explicit prices and amounts. It has no pricing or fee logic. `FeeRequestManager` is the reference wrapper: it computes a per-asset fee, forwards the pool's committed prices, asks the pool's hub policy about the same call as the original manager, and calls `Hub.managerCall`. It refuses a call the policy would time-lock (`NotInPolicy`), so a time-locked fill goes to `OrderBook` directly, and it must itself be a hub manager of the pool.

**Mechanics.** A fill converts the net amount at the supplied prices (`net < fill` is a retained fee, `net > fill` a pool-funded rebate). A fill that converts to zero is rejected. A cancellation carries `amount` and `net`, `net <= amount`. A fill opens a gateway batch around its callback and runs `lockCallback`, so its body is callable only from that batch. `fromHub` is reachable only through the Envoy.

**Edge cases.** Fill amounts and prices are manager inputs, bounded by the optional hub policy (`StdHubPolicy`: `maxFulfillPriceDeviation`, `maxFeeBps`, `maxRebateBps`, each switched off by `type(uint128).max`). `OrderBook.hub` is an immutable, so a hub redeploy does not carry outstanding orders.

### 2.10 Deployment and registration (`VaultFactory`, Envoy configuration path)

**Purpose.** `VaultFactory.deploy(poolId, scId, asset, tokenId, payload)` is permissionless and deploys with CREATE2. The payload is `abi.encode(VaultPlugins, uint64 variant, uint256 foldHorizon)`, and the address commits to the position, plugins, horizon and variant. The hub's `updateVault(DeployAndLink)` registers and links the vault at that address, `UpdateManager` grants it the pool's spoke manager role, and `SetVault` through the share token registrar optionally sets the ERC-7575 pointer. A vault the pool never links is inert, and a front-runner deploys exactly the vault the payload names.

**Configuration path.** Plugin settings travel `Hub.managerCall`, then a message (a direct call when the target is on the hub's chain), then the Envoy, then `target.fromHub(poolId, payload)`. Targets accept `fromHub` from the Envoy only and, where they configure a vault, check the vault belongs to the calling pool in the registry (`spokeRegistry.vaultDetails`) as well as by the vault's own `poolId()`, never by the vault's claim alone.

![Two sequences: configuring a target through the hub, a message and the Envoy, and filling an order with the checks at each step](https://raw.githubusercontent.com/centrifuge/protocol/vdk/docs/architecture/vaults/configuration-path.svg)

### 2.11 Investor router (`src/vaults/VaultRouter.sol`), out of scope

Out of scope for this engagement. It is described because investors reach the vault through it, and the vault's behavior toward it as a caller is in scope.

**Purpose.** The investor-facing entrypoint, separate from `VaultRequestRouter`. It bundles approvals, requests, claims and cross-chain share transfers into one `multicall`. It is endorsed by Root so it can hold shares mid-batch, and an investor makes it their operator with `vault.setOperator(router, true)`, which lets anyone claim their settled requests to them through it. A cross-chain share transfer through it needs the pool to grant the router the Bridger role (see 6.1).

**Expected inputs.** It acts only for its caller, or claims for a controller that made it their operator, to that controller. It refuses any controller of a request other than its caller. It is **not** a custodian: nothing is enforced to be left in it between transactions, so a batch must spend what it brings (as on v1).

**Edge cases.** A multicall funds one cross-chain share transfer with its value (`ValueAlreadySpent` on a second). An instant deposit through the router reaches the instant policy as the router.

## 3. Deployment Environment

### 3.1 Supported Chains

The protocol is hub and spoke. A pool is managed on one hub chain and distributed on spoke chains, where vaults live. A pool whose hub and spoke share a chain uses the same contracts and delivers messages locally.

The VDK is not deployed on any chain yet. It will roll out incrementally, and its spoke half only to chains that meet its deployment requirements (below, chiefly a raised contract size limit), not to every chain the protocol runs on. Chain-specific findings are valid only for the chains named when it is deployed.

What matters for validity on a chain:
- **Code size.** `Vault` is about 49 kB of runtime code. The spoke half (`VaultFactory`, `VaultRequestRouter`, `VaultRouter`, `SpokeOracle`, the request policies, `ReserveInstantPolicy`, `VaultLiquidityRoute`) deploys only where the chain config sets `network.vaults`, which needs a chain whose contract size limit fits them, such as the 64 KiB code and 128 KiB initcode of EIP-7954 (the deployment tooling calls it by the earlier EIP-7907) or a larger limit of the chain's own. The hub half (`OrderBook`, `FeeRequestManager`) fits EIP-170 and deploys everywhere.
- **EVM version.** Solidity 0.8.28, compiled for cancun. Transient storage is used (gateway batching, the router's value tracking). Gas benchmarks are taken under cancun.
- **Messaging.** Cross-chain messages are carried and verified by the pool's adapter set, or the global one where the pool has none. The protocol guardian can pause messaging on a chain immediately: the gateway then refuses sends, inbound messages, retries and repayments. On a paused spoke, unbatched requests, flushes and requests that roll a closed window revert, while a batched request joining an open window still escrows. Fills and price updates stop arriving, claims keep working, and the instant lane keeps trading at the last price until `maxAge` or a local pauser closes it. Where the hub is on the same chain nothing crosses the gateway, so the pause stops nothing in the VDK there.
- **Mempool.** MEV, front-running and sandwiching around price updates, fills and configuration are out of scope (see 6).

### 3.2 Tokens

The vault asset is a **plain ERC-20 only**: non-rebasing, no transfer fee, no transfer hooks or callbacks, not pausable or blocklistable (`deploy` requires `tokenId == 0`, so ERC-6909 and ERC-721 are not expressible). Asset onboarding is the pool's responsibility and has to rule other tokens out: `requestDeposit` notes and reserves the **requested** amount rather than the balance delta, and the instant deposit path accounts before it pulls, so a fee-on-transfer or rebasing asset over-notes the holding. Findings that need a non-standard asset are not valid.

The share token is the pool's `ShareToken` with a role hook.

### 3.3 External Integrations & Dependencies

- **Centrifuge core (`src/core`).** `Spoke`, `SpokeRegistry`, `Escrow`, `SnapshotQueue`, `Hub`, `Gateway`, the Envoy and the holdings accounting. Trusted and specified in [`docs/SPECIFICATION.md`](https://github.com/centrifuge/protocol/blob/vdk/docs/SPECIFICATION.md). Core has its own audits (section 5) and formal verification.
- **Cross-chain messaging providers.** Trusted for delivery. Late, reordered or retried messages are in the cantina out-of-scope list. The VDK relies on the core guarantee of exactly-once application and on the gateway's retry of failed messages.
- **Basin.** A third-party liquidity venue behind `BasinLiquidityRoute`. Its solvency and terms are out of scope beyond how the route measures delivery and books the result.
- **Underlying vaults.** For `VaultLiquidityRoute`, another pool's VDK vault. Treated as a hostile callee for reads (`staticcall`, gas capped, a revert reads as zero) and consented by name. On a draw the route refuses an underlying that pushes in more shares than the draw released (`ExcessShares`) or takes more than it released (`ExcessSharesTaken`).
- **Hub-side execution policy (`StdHubPolicy`).** Optional, out of scope and trusted. Classifies a pool manager's calls as immediate or time-locked and bounds prices, fees and rebates.
- **Accounting managers (`NAVManager`, `SimplePriceManager`) and the `src/misc` libraries** (`MathLib`, `ReentrancyProtection`). Out of scope and trusted.

## 4. Roles, Permissions & Trust Model

### 4.1 Privileged Roles

- **Root / protocol governance.** Fully trusted. The only ward of a deployed vault, with `rely`/`deny` and `Recoverable.recoverTokens` (the vault holds no funds at rest, so recovery is not a drain path). Granting Root ward access goes through Root's timelock: 48 hours on mainnet, a deployment value a Root ward can file anywhere up to 4 weeks. The protocol guardian can pause cross-chain messaging immediately. A Root ward can replace a pool's hub policy outside that policy (`Hub.setPolicy`), the break-glass path, which needs ward access and so the timelock.
- **Pool hub manager.** Trusted within its own pool, untrusted toward other pools. Fills and cancels orders at prices and fees it chooses (bounded by `StdHubPolicy` when installed), changes instant terms, the fee manager's fee, routes, limits, oracle pause and pausers, router extra gas and the share token's hook through the Envoy, links and unlinks vaults, grants or revokes the spoke manager and Bridger roles, sets the pool's spoke request manager, updates members and freezes, names hook managers, adds wards to its share token through the registrar, and moves pool assets. It must not be able to reach another pool's funds, bypass `StdHubPolicy`'s classification through the in-scope contracts, or escape a bound an in-scope contract states.
- **Spoke managers.** Trusted within the pool. Every VDK vault is one. They cannot pause the oracle unless the pool also names them pausers.
- **Hook managers.** Addresses the pool names per share token from the hub. Trusted by the pool. Each can freeze, unfreeze and update members of that token on the spoke at once, outside the hub policy.
- **Share token wards.** Addresses the pool adds to its share token through the registrar (`UpdateWard`). Fully trusted by the pool: they can mint, burn and move its token with authorized transfers.
- **Bridger.** An address the pool lets move its shares across chains. Through `VaultRouter` the role is checked against the router (6.1).
- **Oracle pausers.** Addresses the pool names on `SpokeOracle` from the hub. Each can pause the pool's instant lane on that chain at once, and cannot unpause. Trusted by the pool.
- **Sentinels.** Can veto a pending authorization of a pool manager. Cannot create one.
- **Sponsor.** A pool-trusted party allowed on a vault's instant policy to credit controllers.
- **Adapter manager and gateway manager.** Trusted by the pool. Can set or block the pool's message sessions and clear failed messages, so they can inject messages as if from the hub. The pool is expected to hold them in a multisig; the code does not require it.
- **Investors, operators, keepers, relayers, anyone calling a permissionless function.** Untrusted. They must not be able to extract value, lock funds or corrupt ledgers when the pool's components are honest.
- **Pool-chosen plugins** (request policy, instant policy, liquidity route, oracle, settlement observer, role hook, request observer, and the pool's spoke request manager, which passes the vault's `onlyRequestManager`; the shipped one is `VaultRequestRouter`). Trusted by their pool and the stack calls them plainly (no gas caps, no fallback values) except for the single `QUOTE_GAS` cap on an underlying's quote. A component that reverts, burns gas, misreports or re-enters harms that pool's own users only. A component of one pool that harms another pool or the protocol is in scope.
- **Upgrade authority.** None for the vault: it is immutable, with no setter and no proxy. Configuration changes by deploying a new `variant`. The core is controlled by Root through the guardian contracts and Root's timelock. A pool can add wards to its own share token through the registrar without Root.

What stays in scope even when a component misbehaves is spelled out in [`vdk.md`](https://github.com/centrifuge/protocol/blob/vdk/docs/audits/out-of-scope/vdk.md#what-stays-in-scope-even-when-a-component-misbehaves): cross-pool isolation, protocol-level resources, the bounds the code claims to enforce, untrusted parties against honest components, and the shipped implementations against their own spec rows.

### 4.2 Configurable Parameters & Valid Ranges

Judges assume trusted roles configure values within these ranges. A value outside them, or a bound a pool switches off with zero or `type(uint128).max`, is the pool's own responsibility.

| Parameter | Set by | Valid range | Notes |
|---|---|---|---|
| `VaultPlugins` (5 slots) | anyone at `VaultFactory.deploy`, linked by the pool | any address; zero for an optional slot | fixed at construction. `requestPolicy` zero means instant only, `instantPolicy` zero means async only. The oracle is required, though not checked at construction: a zero oracle makes every price read revert |
| `variant` | deploy payload | any `uint64` | the address commits to the position, plugins, horizon and variant |
| `foldHorizon` | deploy payload | zero (default) or `>= policy.maxOpenBuckets()`, otherwise `InvalidFoldHorizon` (also when a policy reports zero open buckets) | no upper bound. A large horizon costs gas on the pool's own claims and, on unbatched vaults, on settlement callbacks. Eight keeps a week of daily windows |
| `PerRequestPolicy` transfers flag | constructor | bool | whether its positions are transferable |
| `PerPeriodPolicy.window` / `offset` | constructor | `offset < window` (`InvalidOffset`, which also refuses a zero window) | `window` is the dealing period in seconds |
| `depositNotice` / `redeemNotice` | constructor | any `uint64`, zero by default | notice under one window is a cutoff before each close. The policy's `maxOpenBuckets` is ceil(max notice / window) + 1, which sets the `foldHorizon` floor |
| `ReserveInstantPolicy` `depositFeeBps` / `redeemFeeBps` | `fromHub` (hub manager) | `0` to `9,999` each (`InvalidFees`) | basis points of the gross, rounded up. Production value is the pool's choice. A `Terms` message replaces the whole config |
| `maxReserve` | `fromHub` | `0` to `type(uint128).max` | zero closes instant deposits |
| `redeemEnabled`, `gatedDeposit`, `gatedRedeem` | `fromHub` | bool | allowlists key on the caller |
| `feeRecipient` | `fromHub` | any address, zero retains the fee | |
| Sponsors, depositor and redeemer allowlists | `fromHub` | per vault, empty by default | |
| Oracle pausers | `fromHub` (hub manager) | any address | naming or removing one waits out the hub policy's delay |
| `SpokeOracle.maxAge` / `maxSkew` | constructor | canonical: 1 day and equal to `maxAge` | zero disables the bound (a pool deploying its own oracle owns that) |
| Oracle pause | hub, or a pauser the pool names from the hub | per pool | a pauser's pause is immediate on its chain; a hub pause is immediate only on the hub's own chain, elsewhere it waits out the hub policy's delay. Unpause is hub-only |
| `FeeRequestManager` fee rate | `fromHub`, per pool and asset | strictly below 10,000 bps (`FeeTooHigh`), and at most the hub policy's `maxFeeBps` | applied when a fill executes. Under a `StdHubPolicy` that pins the `OrderBook`, a fill whose fee exceeds the policy's bound is time-locked, so `FeeRequestManager` refuses it (`NotInPolicy`) |
| `OrderBook` request observer | `fromHub` (`SetObserver`) | any address, zero for none | per pool |
| `StdHubPolicy` `maxFulfillPriceDeviation`, `maxFeeBps`, `maxRebateBps` | constructor, per policy instance (anyone deploys one, a pool adopts it) | `maxFulfillPriceDeviation` a D18 fraction, `0` exact match; `maxFeeBps` and `maxRebateBps` at most 10,000 (`InvalidConfig`); each off at `type(uint128).max` | a call outside the bounds is time-locked, not reverted |
| `StdHubPolicy` `delay`, `expiry`, `escalation`, price guards, pins (`spokeOracle`, `orderBook`, `bridgingHook`) | constructor, per policy instance | `delay > 0`, `escalation > delay`, `expiry > 0` (`InvalidConfig`); a zero price guard is off; a zero pin makes every call to that target wait out `delay` | the delay is what time-locks the calls this doc calls delayed |
| `StdHubPolicy` allowlist | constructor, per policy instance | per pool, caller and selector | an allowlisted caller may invoke only its listed selectors (`CallerNotAllowed`); it confines by selector, not by target (6.1) |
| `VaultRequestRouter` extra gas | `fromHub` | up to what keeps a request within the network's `maxBatchGasLimit`, otherwise requests revert `BatchTooExpensive` | funds a hub request manager or request observer heavier than the benchmark. Callbacks are funded by each fill's own `extraGasLimit` |
| `BasinLiquidityRoute` limit | `fromHub`, per drawing vault | any `uint128` | the line is the lower of the limit and the credit |
| `BasinLiquidityRoute` credit | `setCredit` by the venue's liquidity provider, per drawing vault | any `uint128` | no pool check |
| `VaultLiquidityRoute` routes and consent | `fromHub` | no duplicate position (`DuplicateRoute`), not the vault itself (`SelfRoute`), a linked underlying (`UnknownVault`) of the same asset (`AssetMismatch`), a consent per routing vault from the underlying's pool (`NotConsented`) | quote gas capped at 400,000 per read, up to four reads per underlying |

### 4.3 Off-Chain Components & Operational Assumptions

- **Keepers.** Someone calls `flushRequest` for windows that close without a following request, and `foldRequest` for positions outside a controller's horizon (relevant for `PerPeriodPolicy` when an investor holds more windows than their horizon), and retries failed gateway messages. These are permissionless and cost only gas. Keeper availability and gas policy are out of scope. A permissionless call that stays correct is in scope.
- **Pool manager operations.** Fills and cancellations, price updates to the hub, topping up the escrow when a settlement over-reserves, initializing the hub holding of the asset (`initializeHolding`) before the first fill (without it `FeeRequestManager` refuses every fill with `HoldingNotInitialized`, and `StdHubPolicy` with its price guard on holds a direct `OrderBook` fill to its delay).
- **Indexers, SDKs, frontends.** Out of scope, including correctness against emitted events. `BucketSettled`, `BucketOpened`, `RequestFolded` and `OutsideHorizon` carry what a keeper needs.
- **Relayers.** The protocol batches messages and can pay message costs from the pool's gas subsidy, so an investor pays for their own spoke transaction and for any cross-chain share transfer. A request sent without a subsidy goes out unpaid and waits for someone to `repay` it.

## 5. Previous Audits

One audit of the VDK to date:

- **B612 Security, "Vaults V2" security review** ([`2026-10-B612-Vaults-V2.pdf`](https://github.com/centrifuge/protocol/blob/vdk/docs/audits/2026-10-B612-Vaults-V2.pdf)). Review of 26 to 30 October 2026, issued 11 November 2026, of the vault stack at commit `1b2f80bdd` (fixes reviewed at `c2574ad95`). Scope was the vault stack in `src/vaults` except `VaultRouter.sol`, plus `IERC8161`, the share token hook and its interfaces, `ShareTokenRegistrar`, and the `StdHubPolicy` and `src/misc` changes, almost entirely full files. Result: 0 critical, 1 high, 0 medium, 4 low, 1 informational, overall score 4 of 5 ("Solid"). All are resolved except L-1, which is acknowledged.

| ID | Finding | Status |
|---|---|---|
| H-1 | Basin debt above the drawing network's equity is omitted from NAV, inflating the share price | Resolved |
| L-1 | After vault retirement the claim functions fail | Acknowledged |
| L-2 | A malicious underlying vault can block every instant exit of the routing vault | Resolved |
| L-3 | Upward rounding in fulfillment rebate validation weakens the configured rebate ceiling | Resolved |
| L-4 | Async max views can return zero even though a refund-only claim is executable | Resolved |
| I-1 | Tokens sent directly to the liquidity routes cannot be recovered | Resolved |

The code in scope has since changed: the vault was restructured after that review (the request policies' bucket assignment and the unbatched fold moved into the vault), so the report covers an earlier form of it. The acknowledged L-1 is known: it is the retirement behavior described in 6.1 ("Deployment and configuration"). The other five findings are resolved, and one that still reproduces is not known. The specification's `n` rows and [`vdk.md`](https://github.com/centrifuge/protocol/blob/vdk/docs/audits/out-of-scope/vdk.md) are also known items.

- **Formal verification of the VDK:** none yet. No formal verification models exist for the vault, and core's formal verification does not cover the kit.
- **The protocol core the VDK builds on** has been reviewed by several firms (Spearbit, Sherlock, Blackthorn, yAudit, burraSec, Cantina and others). Reports are in [`docs/audits`](https://github.com/centrifuge/protocol/tree/vdk/docs/audits) and do not cover the VDK (the B612 report above is the only VDK audit). Issues in those reports are known for the code they cover.

## 6. Known Issues, Accepted Risks & Design Decisions

The full list is the specification's `n` rows plus [`vdk.md`](https://github.com/centrifuge/protocol/blob/vdk/docs/audits/out-of-scope/vdk.md), which extends [`cantina-bug-bounty.md`](https://github.com/centrifuge/protocol/blob/vdk/docs/audits/out-of-scope/cantina-bug-bounty.md). A submission that matches an item there is invalid, with two exceptions. A report that shows harm beyond what an `n` row states is in scope. So is one that breaks a guarantee `vdk.md` keeps in scope even when a component misbehaves: cross-pool isolation, protocol-level resources, the bounds the code states, untrusted parties against honest components, and the shipped implementations against their own spec rows. This section summarizes the items by component. Where a summary and its source differ, `vdk.md` and the specification rows govern.

### 6.1 Known Issues by Component

#### Vault, settlement and horizon

- **Settlement is unordered across buckets and fair only within one.** A bucket splits floor pro-rata and split-invariantly. Across buckets there is no ordering, so which request a manager fills is off-chain discretion. Only `PerPeriodPolicy` gives a fairness property, among contributors of the same window.
- **A request is priced at fulfillment, not at request.** The price is a manager parameter of the fill. A request pending across a write-down can be filled at the pre-write-down price. The bound is `StdHubPolicy.maxFulfillPriceDeviation`, a pool parameter.
- **Shares issued are not bounded on-chain by assets received.** Fill amounts and prices are manager inputs and the vault trusts its registered request manager. The conservation rows (claimable backing, the `REASON_REDEEM` aggregate, value conservation across a fill) hold only when a settlement's legs are applied together, as `VaultRequestRouter` does. A request manager the pool registers itself can call `issueShares`, `revokeShares` or `approveDeposits` apart from the ledger legs, with any amounts, and is trusted for its own pool.
- **Exactly-once settlement is inherited from core**, not enforced here. `settle` accumulates: it rejects a spent or unflushed bucket and a settlement beyond what the bucket sent, so a duplicate within that bound double-counts.
- **A deferred fold.** A fold that would push a `uint128` ledger counter past its maximum changes nothing and the position stays pending until the ledger is claimed down. It takes on the order of 256 unclaimed maximal fills at ordinary share prices, fewer only near the D18 minimum, and a settled window pushed onto a victim under `PerPeriodPolicy` can cause it. Saturating would distort the pro-rata ratio, so the fold waits (`FoldDeferred` blocks a transfer meanwhile).
- **A batch outside the horizon needs `foldRequest`.** A full horizon evicts the oldest position even while unsettled when the controller's own request needs the slot, but never one of the controller's open buckets, and a gifted position takes only a free slot. A batched position that finds no slot waits for the permissionless `foldRequest`, which also restores the `max*` views. An unbatched bucket still folds as it settles.
- **Pending-view dust.** On a shared redeem bucket, contributors' `pendingRedeemRequest` can sum to one share unit each above the bucket's pending. It is a view artifact, not a claim the escrow must back.
- **A bucket's live contributions can sum below its `total`.** `total` sums every contribution ever made, and a fold that closes a contribution out of a spent bucket deletes it. No slice reads the live sum and a spent bucket takes no further settlement or contribution, so nothing moves. An indexer should not rebuild `total` from the live contributions.
- **Request ids are not unique over a vault's lifetime.** `PerInvestorPolicy` reuses a retired sole-owner id. Key a secondary market on the controller too.
- **No investor cancel.** Cancellation is order-level and the pool's.
- **Rounding and dust** stay in the escrow in the vault's favor: up to one unit per contributor per settlement, a slice whose counter-unit floors to zero, and `max*` views at a capacity of a few units. A route draw rounds the underlying's shares up, and `StdHubPolicy`'s fee bound rounds up, each by up to one unit ([`vdk.md`, "Rounding and dust"](https://github.com/centrifuge/protocol/blob/vdk/docs/audits/out-of-scope/vdk.md#rounding-and-dust)).
- **A reservation can exceed what the escrow holds.** `Vault._reservePayout` counts only the vault's own redeem reservation, and core `Escrow.reserve` does not bound the total, so sibling vaults on one position can over-reserve. A redeem payout is also checked against the holding's total, which counts pending deposits' cash but not their reservations, so it can reserve past the holding while a deposit's cash is reserved. No funds move wrongly: while reservations exceed the holding, every withdrawal of that holding waits, until the pool tops up the escrow or a deposit leg settles. This is a known issue and is documented as a non-guarantee.
- **A deposit's reservation is keyed by request id**, which a sole owner's later top-ups share, so after a manager unlocks a deposit early its approval can release the cash of a top-up that is still pending.

#### Instant lane, oracle and fees

- **Arbitrage against a stale or jumped price** where the pool chose a small or zero spread, and any gain from the gap while the spoke price lags whatever spread the pool quotes, are out of scope. The instant lane trades at the price the oracle last had notified within `maxAge` and `maxSkew`, and a round-trip spread offsets the gain only when both legs are instant: an instant deposit followed by an asynchronous redemption pays the entry fee but not the instant exit fee, and exits at the hub's price.
- **Instant redeem capacity is a draining budget.** There is no cumulative volume limit, by design.
- **Deposit capacity is global per vault**, not per receiver.
- **`mint` and `withdraw` do not bound a policy's fee.** The vault bounds the fee below the amount only on `deposit` and `redeem`.
- **Cash a manager sends to the escrow for an async redemption counts as available balance** until its settlement callback reserves it, so instant redeemers can take it first.
- **Price magnitude and rate of change are not bounded by the oracle.** That is pool-level policy. At an extreme ratio between the share and asset prices, the capacity clamps and the role-check estimates in `VaultPricingLib` revert `MathLib.MulDiv_Overflow` rather than saturate.
- **The lane follows the caller's state.** A 2-argument `deposit`, `mint`, `redeem` or `withdraw`, and the owner's 3-argument `redeem` or `withdraw`, is a claim while the caller has something claimable or pending on that side, and otherwise an instant trade. Once a keeper or the router has claimed for an investor, the investor's own such call buys with the caller's allowance or sells wallet shares through the instant lane, and pays its fee.

#### Liquidity routes

- **A shared route is shared across pools.** The venue's liquidity is not reserved per vault and `BasinLiquidityRoute` credit lines are each quoted against the whole venue. Whoever draws first takes it.
- **A top vault's holders can redeem at its own price** after an underlying's price falls and before the top price follows, and the underlying's exit fee falls on the routing pool.
- **The hub books a Basin draw as a liability** only once the pool initializes the liability holding. Until then NAV overstates by what is owed. A surplus a venue returns beyond a draw is a donation to the escrow.
- **A Basin receivable can sit above a lowered line.** The line is checked when a vault draws, not afterwards. Lowering the limit or the credit below what is owed stops new draws and forces no repayment, so the receivable stays above the line until a spoke manager of the pool repays it.
- **A route draw releases the token the registry names as the underlying's share token,** which the underlying pool's registrar chooses. A pool that routes into an underlying whose registrar names a token outside the registry (a retired share token, say) can have its own holding of that token released. This is out of scope even though the token reaches another pool's vault, since the routing pool chose to route into that underlying, and which foreign tokens are safe to hold is its own judgement.
- **Venue and underlying-vault solvency** is out of scope beyond how the route measures delivery.

#### Share token role hook

- **The hook treats every pool's escrow as a member of every class in every role,** so a non-member holder can move a restricted token into another pool's escrow and exit through that pool's vault.
- **A refund goes to the controller the request named,** not the owner who funded it. A hook whose `exit` is looser than its `transfer` lets that controller receive shares it could not have been sent. The shipped hooks are unaffected, and a pool with such a hook is expected to allow no sponsors and give its vaults an instant lane.
- **A refund of a cancelled deposit to a receiver other than the controller** is a `RedeemClaim`, which the payout role refuses for an endorsed contract under the `freelyTransferable` and `fullRestrictions` presets. The controller can take it to itself and forward it.
- **The vault's callbacks need only the request manager and not a link,** and the hook cannot tell the vault's call from a forged role check by a third party. Both are harmless with the shipped components.
- **A swapped or misconfigured hook** that blocks claims or transfers is the pool's responsibility.

#### Sponsors, transfers and horizon gifts

- **A sponsor can credit any controller,** including the router or a fund-of-funds route, and the pending or claimable position holds that controller's instant lane in async until settled and claimed. Sponsors are pool-trusted. Nobody can claim for the router or a route: a refund credited to the router stays stranded, a filled deposit goes to the router's next depositor, and a cancelled redeem makes every router deposit on that vault revert for good, while a route's redeem-side claim is spent by whichever routing vault draws first.
- **Without an instant lane anyone can credit any controller,** and a request transfer needs no consent from its recipient, as ERC-8161 specifies, though the shipped hooks hold the recipient to the request's bar (a lapsed controller can still transfer a pending position to a member; only a frozen one cannot move it). A gift or transfer takes only a free horizon slot and never evicts one, and the horizon fold or `foldRequest` restores claims. A gift can still take the slot a closed, unsettled position would have kept, so the controller's next own request evicts that one sooner, a delay `foldRequest` ends.

#### Router and request transport

`VaultRouter` is out of scope (see the scope at the top); its items are kept so a report against the vault can tell them apart.

- **`VaultRouter` is not a custodian:** what a batch leaves in it goes to the next caller. An instant deposit through it reaches the policy as the router, so a caller allowlist would have to name the router, which opens the lane to every account that can receive shares. The router checks the bridger role and bridge limits against itself and not the holder, so once a pool grants the router the role, every holder can bridge through it.
- **`VaultRequestRouter` has no reentrancy guard and can strand ETH sent to it directly:** `receive()` is unguarded and there is no sweep.
- **A request is worth a cross-chain message however small.** A third party can open one-wei requests for any controller, each costing the pool a message from its subsidy, unless the issuer constrains requests through the hook, an allowlist or the request policy.
- **In-flight settlements survive an unlink** only as stalled and retryable callbacks, applied on relink.

#### Deployment and configuration

- **`VaultFactory.deploy` is permissionless,** so anyone can deploy a vault for any pool at its predictable address. It acts for no pool until linked.
- **After a vault is retired its claim functions fail** once the pool revokes its spoke manager role, because every claim pays through the Spoke as a call by the vault (B612 L-1, acknowledged). Unlinking does not revoke the role. A pool retires a vault by draining it, then unlinking, and keeps the role until claims are paid. `UpdateManager(false)` while claims are outstanding freezes them with `NotManager`.
- **Configuration messages are plain overwrites with no nonce.** A configuration message that fails on the spoke (typically one racing `DeployAndLink`) stays in the gateway and can be retried later, overwriting what the pool configured since (a stale pause of `false`, stale terms, stale routes or consent). Core gives no ordering or freshness guarantee for irregular messages. A pool clears a failed configuration message it does not want applied through `Gateway.clearFailedMessage`.
- **`PerPeriodPolicy` with `offset` ahead of the chain clock** panics until the clock passes the offset, reachable only on a chain whose clock is below the window length.
- **Deployment constraints a pool is expected to satisfy:** a restricted share class is gated by its own hook and its registrar must support `authTransferFrom` (otherwise the vault cannot serve async or instant redemptions), an instant lane needs a non-zero price-freshness bound (and a tighter `maxSkew` where the pool quotes a tight spread), and a liquidity route is shared across pools.
- **Gas benchmarks assume the cancun schedule.** What a later fork can move (EIP-7907's per-word charge for cold code loads) is not reserved. A message that runs short fails on the spoke and is retried with more gas.
- **Deployment cost.** A vault costs about 10M gas to deploy today and about 75M under the EIP-8037 draft schedule (`VaultFactory.t.sol`, `testDeploymentCostToday`). On a chain that raises the size limit together with that pricing, the draft figure is the one that applies. That cost is a known property of the design, not a finding. The options are in [ARCHITECTURE, "Deployment cost under EIP-8037"](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/ARCHITECTURE.md#deployment-cost-under-eip-8037).

#### Hub request managers

- **`FeeRequestManager` applies the fee in force when a fill executes.** A fee change a hub policy delays still reaches pending requests, bounded by the policy's maximum. A fill whose fee rounds its net to zero is rejected and can only be cancelled.
- **`StdHubPolicy` cannot force a pool's managers through `FeeRequestManager`** instead of `OrderBook`. A manager who may send `managerCall` may also send a direct fill with its own prices. A per-target allowlist would close it and is not built.
- **`OrderBook.hub` is immutable.** A hub redeploy does not carry outstanding orders.

#### Out of scope by category

Everything outside the scope stated at the top is out of scope. Everything in [`vdk.md`](https://github.com/centrifuge/protocol/blob/vdk/docs/audits/out-of-scope/vdk.md) "Out of scope" applies too, among it: the specification's non-guarantees, deployment constraints and listed ERC deviations, pool-chosen components and trusted managers behaving badly, plain-ERC-20 assets only, third-party venues and the shared singletons, economics and market behavior (MEV, bank runs, arbitrage), griefing that costs the attacker more than the victim or only hits the attacker's own pool, temporary reverts that a manager or governance action clears (delay, not loss), rounding and dust, keepers, relayers, SDKs, frontends and indexers (availability and correctness), the accuracy of non-normative documents, migration from v1, tests and mocks, and informational or gas findings.

## 7. Build, Test & PoC Setup

Toolchain: Foundry, Solidity 0.8.28, Cancun EVM, optimizer settings from `foundry.toml`. Use the `forge` the repo CI pins (`nightly-8e47a24a36283247c57fd735d1e6db961ca5efc1` in `.github/workflows/ci.yml`). The integration tests need the IR build first.

Build

```bash
forge build
FOUNDRY_PROFILE=ir forge build   # needed once before integration tests
```

Run the VDK test suites

```bash
forge test --match-path "test/vaults/*"        # unit, fuzz and invariant suites for the vault stack
forge test --match-path "test/hooks/*"         # role hook and vault action tests
forge test --match-path "test/integration/*"   # end to end, liquidity routes, security regressions
```

Single test with traces

```bash
forge test --match-test <name> -vvvv
```

Gas bounds of the horizon

```bash
forge test --match-path "test/vaults/FoldHorizonGas.t.sol"
```

`foundry.toml` pins `isolate = false`; the gas tests assume it, so do not pass `--isolate`.

Fork tests and environment variables: none. Tests run against a local deployment.

Integer overflow: Solidity 0.8.28 checked arithmetic, with explicit saturating math (`MathLib.saturatingSub`) and explicit `uint128` bounds in the ledger. Narrowing casts use `MathLib`'s checked `toUint128` and its siblings or sit behind the comparison before them, and a rebate is negated in `int256`, so `int128.min` becomes a rebate of `2^127` rather than overflowing ([SPECIFICATION](https://github.com/centrifuge/protocol/blob/vdk/src/vaults/SPECIFICATION.md), "The signed instant fee never wraps"). Fold deferral on `uint128` overflow is intentional (6.1).

Fuzzing: the recon suites (`test/integration/recon-end-to-end`) drive the vault end to end under Echidna and Foundry, with invariants and replay tests, and name the SPECIFICATION properties they cover.

Where to put a PoC and which base test to inherit. Unit PoCs follow `test/vaults/Vault.t.sol` (`VaultTest`, a vault over mocked spoke, escrow and share token). Integration PoCs build on `EndToEndFlows` in `test/integration/EndToEnd.t.sol`. Its base, `EndToEndDeployment`, deploys the protocol on a hub and a spoke chain; `EndToEndFlows` adds the helpers that create the pool and share class, configure the spoke and prices, deploy and link a VDK vault with its plugins, request, fill and cancel. This scaffold runs as is:

```solidity
// test/integration/PoC.t.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {EndToEndFlows} from "./EndToEnd.t.sol";
import {IAsyncVault} from "../../src/vaults/interfaces/IAsyncVault.sol";
import {RequestId} from "../../src/core/types/RequestId.sol";
import {IShareToken} from "../../src/token/interfaces/IShareToken.sol";
import {IntegrationConstants} from "./utils/IntegrationConstants.sol";

contract PoC is EndToEndFlows {
    function test_PoC() public {
        _configurePool(true); // same-chain hub and spoke; false for two chains
        _configurePrices(IntegrationConstants.assetPrice(), IntegrationConstants.sharePrice());
        IAsyncVault vault = _deployVault(); // _deployInstantVault() for the instant lane

        RequestId requestId = _requestDeposit(vault, USDC_AMOUNT_1);
        _fulfill(true, requestId, USDC_AMOUNT_1);

        vm.prank(INVESTOR_A);
        vault.deposit(USDC_AMOUNT_1, INVESTOR_A);

        assertGt(IShareToken(vault.share()).balanceOf(INVESTOR_A), 0);
    }
}
```

See `test/vaults/LiquidityRouteIntegration.t.sol` for routes, and `test/integration/recon-end-to-end` for the fuzzed handlers. Prank as the actor a call is meant to come from, and check that a negative auth test reverts for the reason it names.

## Appendix A: Topics by component type

### A.2 Share / receipt token issuance (Vault)

- **Share price.** A valuation from hub-notified prices: `totalAssets() = convertToAssets(totalSupply())`. It can decrease when the hub writes the NAV down, and existing holders bear it. Async claims convert at the ledger's blended price, so a claim is unaffected by later price moves.
- **First-depositor and inflation attacks.** Unreachable by construction: no ratio of balances exists. A raw transfer to the escrow moves no price and no capacity, and instant capacity reads the escrow's internal accounting (`total - reserved`), not `balanceOf`. Rounding dust accruing to the pool (the Euler stealth-donation generalization) applies but closes only through a hub round trip and a NAV recompute, and accrues to all holders linearly.
- **Minimum amounts.** None. A request of one wei costs the pool a cross-chain message (6.1).
- **Transferability.** The share token is transferable under its transfer hook. Pending requests are transferable (ERC-8161) where the request policy supports it.

### A.5 Cross-chain messaging

- **Messaging.** Core gateway, verified by the pool's adapter set or the global one, with retry of failed messages. The VDK relies on exactly-once application from core.
- **Trusted senders.** The router's inbound callbacks are ward-gated and checked against the registry. `fromHub` targets accept the Envoy only.
- **Failed messages.** A message that fails on the spoke stays in the gateway for anyone to retry. Callbacks to an unlinked vault revert and apply on relink. On a same-chain hub nothing is stored: the hub's call itself reverts. Configuration messages are overwrites with no nonce (6.1).
- **Gas.** Priced by `GasService` benchmarks plus the message's extra gas: the pool's `VaultRequestRouter` setting for requests, each fill's `extraGasLimit` for callbacks. A message that runs short fails and is retried with more gas.
- **Pause.** The guardian pause stops a chain's gateway: sends, inbound messages, retries and repayments (3.1 has what keeps working). It stops nothing in the VDK of a pool whose hub is on the same chain. A pool blocks its own sessions through its adapter manager.

### A.7 Queues and asynchronous processing

- **Ordering.** No queue and no FIFO. The hub manager fills any bucket in any order and in part. There is no cursor, so an untouched bucket never blocks newer ones.
- **Processing.** Fills are the pool manager's. Flush and fold are permissionless.
- **Repricing.** A request is priced at fulfillment, not at request. The only guarantee between request and processing is that the request is funded and cannot be spent elsewhere.
- **Cancellation.** The pool's, at order level, with gross and net amounts. There is no investor cancel.

### A.8 Routers and periphery

`VaultRequestRouter` is in scope; `VaultRouter` is not, and is described for context.

- **Custody.** `VaultRouter` holds nothing between transactions by contract, not by enforcement. `VaultRequestRouter` holds no funds and no per-request state.
- **`msg.value`.** A multicall funds one cross-chain share transfer, tracked in transient storage.
- **Arbitrary calls.** None: the routers call fixed typed interfaces. `VaultRequestRouter` calls the vault resolved from the request id. `VaultRouter`'s `requestRedeem`, `claimDeposit` and `claimRedeem` call the vault the caller names, without a registry check.
- **Recipients.** A claim through `VaultRouter` acts for the caller, who names the receiver, or for a controller who made the router their operator, paying that controller.

### A.9 Plugins, hooks and modules

- **Registration.** Fixed at deployment of each vault. Anyone can deploy a vault with any plugins, and the pool decides whether to link it. The role hook is the share token's, per share class.
- **Containment.** A misbehaving plugin harms that pool's vault only. The vault does not cap gas or catch reverts of its own plugins, except a single quote gas cap.
- **Failure handling.** A request, instant or settlement hook that reverts stops that action. This is how allowlists, gates and lockups are written. A settlement observer that must not block guards its own external calls.

### A.10 Migration and upgrades

- No upgrade path and no migration from v1 vaults in this release. A new configuration is a new `variant`. The share token's hook has to implement `IRoleHook` (`ShareTokenHook` does, the earlier hook contracts do not), so a live share token needs its hook swapped.

### A.11 Registries and listing

- **Roles.** Anyone deploys a vault through `VaultFactory.deploy`. Only the pool lists it: the hub's `DeployAndLink` registers and links it under the sending pool, and `UpdateManager` grants it the spoke manager role. Registration requires the vault to name the sending pool and share class: core's `SpokeHandler` reads its `poolId` and `scId` and refuses a mismatch (`InvalidVault`), so no pool can register another pool's vault. It does not read the vault's asset, so a pool that registers its own vault under the wrong asset leaves that vault refusing every flow (`VaultNotLinked`), which only that pool can cause.
- **Gating.** `VaultRequestRouter` sends requests and applies callbacks only for linked vaults. Configuration targets take a vault's pool from the registry. The registry records only vaults a pool's `DeployAndLink` registered, and keeps an unlinked one recorded.
- **Revocation.** The pool can unlink a vault. In-flight callbacks then stall and apply on relink. Unlinking leaves the spoke manager role in place, and revoking it with `UpdateManager(false)` freezes outstanding claims (B612 L-1), so a pool retires a vault by draining it, unlinking, and keeping the role until claims are paid.
