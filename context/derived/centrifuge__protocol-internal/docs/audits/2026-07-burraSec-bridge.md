![logo: BURRA SEC wordmark](page_1_image_1_v2.jpg)

# **Token Bridge Audit Report**

Prepared by [Burra Security](https://www.burrasec.com/)

Version 1.0

## **Researchers**

jesjupyter

rotru

ihtisham-sudo

Taridoku

July 23, 2026

---

<table>
<caption>**Contents**</caption>
<tr><td>1</td><td>About Burra Security</td><td>2</td></tr>
<tr><td>2</td><td>Disclaimer</td><td>2</td></tr>
<tr><td>3</td><td>Risk Classification</td><td>2</td></tr>
<tr><td>4</td><td>Protocol Summary</td><td>2</td></tr>
<tr><td>5</td><td>Audit Scope</td><td>2</td></tr>
<tr><td>6</td><td>Executive Summary</td><td>3</td></tr>
<tr><td>7</td><td>Findings</td><td>4</td></tr>
<tr><td>    7.1</td><td>Medium Risk</td><td>4</td></tr>
<tr><td>        7.1.1</td><td>Relayer cannot honor refundAddress</td><td>4</td></tr>
<tr><td>    7.2</td><td>Low Risk</td><td>5</td></tr>
<tr><td>        7.2.1</td><td>gasLimits has no destination-chain dimension</td><td>5</td></tr>
<tr><td>        7.2.2</td><td>Batching TokenBridge.send silently diverts the relayer funding needed for leg 2</td><td>5</td></tr>
<tr><td>    7.3</td><td>Informational</td><td>6</td></tr>
<tr><td>        7.3.1</td><td>Spoke-to-spoke transfers can start with relayer == 0</td><td>6</td></tr>
<tr><td>        7.3.2</td><td>Directly transferred shares are permanently stuck in TokenBridge</td><td>6</td></tr>
<tr><td>        7.3.3</td><td>Existing-root migration omits the TokenBridge endorsement, disabling send for FullRestric-<br />tions shares</td><td>7</td></tr>
</table>


1

---

## 1 About Burra Security

Burra Security offers security auditing and advisory services with a special focus on cross-chain and interoperability protocols and their integrations. Learn about us at [burrasec.com.](https://www.burrasec.com/)

## 2 Disclaimer

A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource, and expertise-bound effort where we try to find as many vulnerabilities as possible. We can not guarantee 100% security after the review or even if the review will find any vulnerabilities. Subsequent security reviews, bug bounty programs, and on-chain monitoring are recommended.

## 3 Risk Classification

<table>
<thead>
<tr><th></th><th>Impact: High</th><th>Impact: Medium</th><th>Impact: Low</th></tr>
</thead>
<tbody>
<tr><th><b>Likelihood: High</b></th><td>Critical</td><td>High</td><td>Medium</td></tr>
<tr><th><b>Likelihood: Medium</b></th><td>High</td><td>Medium</td><td>Low</td></tr>
<tr><th><b>Likelihood: Low</b></th><td>Medium</td><td>Low</td><td>Low</td></tr>
</tbody>
</table>

## 4 Protocol Summary

TokenBridge is a new Centrifuge Protocol contract that moves native share tokens across chains. It exposes a Glacis Airlift-compatible `send()` interface, takes custody of the caller's shares, maps the destination EVM chain ID to Centrifuge's internal chain ID, and forwards the transfer to `Spoke.crosschainTransferShares`, which burns and re-mints the shares on the destination chain.

For spoke → hub → spoke transfers, a configured relayer funds the second leg from the first leg's gas overpayment; when the hub is an endpoint the transfer is single-leg and the overpayment is refunded to the user. Per-pool gas limits are set via an authenticated `trustedCall`.

## 5 Audit Scope

The focus of the audit is `TokenBridge.sol`, but the other smaller changes introduced to files under `src/` in [PR #252](https://github.com/centrifuge/protocol-internal/pull/252) are also in scope.

Scope:

```text
src/
├── admin/
│   ├── interfaces/
│   │   ├── IOpsGuardian.sol
│   │   └── IProtocolGuardian.sol
│   ├── OpsGuardian.sol
│   └── ProtocolGuardian.sol
└── bridge/
    ├── interfaces/
    │   └── ITokenBridge.sol
    └── TokenBridge.sol
```

2

---

# 6 Executive Summary

Over the course of 2 days, the Burra Security team conducted an audit on the [Token Bridge](https://github.com/centrifuge/protocol-internal) smart contracts provided by [Centrifuge.](https://centrifuge.io/) In this period, a total of 6 issues were found.

## Summary

<table>
<tr><td>Project Name</td><td>[Token Bridge](https://github.com/centrifuge/protocol-internal)</td></tr>
<tr><td>Repository</td><td><span style="color:#2580c3">[protocol-internal](https://github.com/centrifuge/protocol-internal)</span></td></tr>
<tr><td>Commit</td><td><span style="color:#2580c3">[867bb92a0a19](https://github.com/centrifuge/protocol-internal/blob/867bb92a0a192ca7393cedf9c2cf53dc8b14f990). . .</span></td></tr>
<tr><td>Audit Timeline</td><td>July 16th - July 17th</td></tr>
<tr><td>Methods</td><td>Manual Review</td></tr>
</table>

## Issues Found

<table>
<tr><td>Critical Risk</td><td>0</td></tr>
<tr><td>High Risk</td><td>0</td></tr>
<tr><td>Medium Risk</td><td>1</td></tr>
<tr><td>Low Risk</td><td>2</td></tr>
<tr><td>Informational</td><td>3</td></tr>
<tr><td>Gas Optimizations</td><td>0</td></tr>
<tr><td>Total Issues</td><td>6</td></tr>
</table>

## Summary of Findings

<table>
<tr><td>[M-1] Relayer cannot honor refundAddress</td><td>Resolved</td></tr>
<tr><td>[L-1] gasLimits has no destination-chain dimension</td><td>Acknowledged</td></tr>
<tr><td>[L-2] Batching [TokenBridge](https://github.com/centrifuge/protocol-internal).send silently diverts the relayer funding needed<br />for leg 2</td><td>Resolved</td></tr>
<tr><td>[I-1] Spoke-to-spoke transfers can start with relayer == 0</td><td>Resolved</td></tr>
<tr><td>[I-2] Directly transferred shares are permanently stuck in TokenBridge</td><td>Resolved</td></tr>
<tr><td>[I-3] Existing-root migration omits the TokenBridge endorsement, disabling<br />send for FullRestrictions shares</td><td>Resolved</td></tr>
</table>

3

---

# 7 Findings


## 7.1 Medium Risk


### 7.1.1 Relayer cannot honor `refundAddress`


**Target:** TokenBridge.sol, ITokenBridge.sol


**Severity:**


- Impact: Low
- Likelihood: High


**Description:** For spoke -> hub -> spoke transfers, `TokenBridge._crosschainTransfer` replaces the user-supplied `refundAddress` with the relayer. The original address is not forwarded, stored, or included in the `Send` event. An event-driven relayer therefore cannot distinguish `refundAddress` from `sender` when returning any surplus after funding leg 2. This contradicts the interface, which identifies `refundAddress` as the recipient of excess gas funds.


**Recommended Mitigation:** Include `refundAddress` in the `Send` event, or define `sender` as the refund recipient for two-leg transfers and document that behavior.


**Centrifuge:** Fixed in [centrifuge/protocol-internal#261](https://github.com/centrifuge/protocol-internal/pull/261/changes/d6dce34c3523f5a7b9526fca0d13dd0472da8ea0)


**BurraSec:** Fix looks good. Refund address now in Send event.

4

---

# 7.2 Low Risk


## 7.2.1 `gasLimits` **has no destination-chain dimension**


**Target:** [TokenBridge.sol](https://github.com/centrifuge/centrifuge-protocol-internal-mirror/blob/867bb92a0a192ca7393cedf9c2cf53dc8b14f990/src/bridge/TokenBridge.sol#L26-L28), [ITokenBridge.sol](https://github.com/centrifuge/centrifuge-protocol-internal-mirror/blob/867bb92a0a192ca7393cedf9c2cf53dc8b14f990/src/bridge/interfaces/ITokenBridge.sol#L23-L30)


**Severity:**

- Impact: Low
- Likelihood: Medium


**Description:** `TokenBridge.gasLimits` is keyed only by `(poolId, scId)`. `send()` resolves the destination chain, but then reads the same `gasLimits[poolId][scId]` entry for every destination that share class supports.


```
mapping(PoolId => mapping(ShareClassId => GasLimits)) public gasLimits;
```


```
GasLimits memory limits = gasLimits[poolId][scId];
```


A pool that bridges the same share class to multiple spokes cannot set route-specific extra gas limits. Operators have to choose one `extraGasLimit` / `remoteExtraGasLimit` pair that works for all destinations, even if one destination needs more execution gas than another. This does not bypass the gateway's destination fee quote, but it does remove the ability to configure execution gas per route.


**Recommended Mitigation:** If different routes can require different execution gas, include destination `centrifugeId` in the gas limit key and in the trusted update payload. If one shared budget is intentional, document that constraint and monitor failed deliveries per route so the shared value can be adjusted before users are affected.


**Centrifuge:** For most cases, the hooks on the destination chains will likely be the same and so the execution gas also. Should they differ, the manager can account for the worst case.


**BurraSec:** Acknowledged


## 7.2.2 **Batching** `TokenBridge.send` **silently diverts the relayer funding needed for leg 2**


**Target:** TokenBridge.sol, Gateway.sol


**Severity**:

- Impact: Low
- Likelihood: Medium


**Description:** For spoke-> hub -> spoke transfers, TokenBridge routes the source-leg surplus to the relayer so it can repay the unpaid second leg. An integrator can call `TokenBridge.send{value: 0}` inside `Gateway.withBatch` and fund the outer batch instead. In batching mode, the per-message refund address is ignored and the surplus goes to the outer batch's refund address. The transfer still emits `Send`, but the relayer receives nothing. A receipt-verifying relayer will leave leg 2 underpaid, while an event-only relayer may fund it without compensation.


**Recommended Mitigation:** Make `TokenBridge.send` revert while the source Gateway is batching, and require the relayer to verify receipt before funding leg 2.


**Centrifuge:** Fixed in [centrifuge/protocol-internal#261](https://github.com/centrifuge/protocol-internal/pull/261/changes/699fab7c91d07bb04fd7a173a756cc2ca86e2374)


**BurraSec:** Fix looks good. `TokenBridge` now reverts with `NotBatchable` if batching.


5

---

## 7.3 Informational


### **7.3.1** Spoke-to-spoke transfers can start with `relayer == 0`


**Target:** [TokenBridge.sol](https://github.com/centrifuge/centrifuge-protocol-internal-mirror/blob/867bb92a0a192ca7393cedf9c2cf53dc8b14f990/src/bridge/TokenBridge.sol#L96-L112), [MessageDispatcher.sol,](https://github.com/centrifuge/centrifuge-protocol-internal-mirror/blob/867bb92a0a192ca7393cedf9c2cf53dc8b14f990/src/core/messaging/MessageDispatcher.sol#L436-L467) [HubHandler.sol,](https://github.com/centrifuge/centrifuge-protocol-internal-mirror/blob/867bb92a0a192ca7393cedf9c2cf53dc8b14f990/src/core/hub/HubHandler.sol#L115-L134) [Gateway.sol](https://github.com/centrifuge/centrifuge-protocol-internal-mirror/blob/867bb92a0a192ca7393cedf9c2cf53dc8b14f990/src/core/messaging/Gateway.sol#L229-L240)


**Severity:**

- Impact: Low
- Likelihood: Low


**Description:** `TokenBridge` integrates a relayer for spoke → hub → spoke transfers: first-leg overpayment is held by the relayer and used to fund the second leg on the hub. NatSpec and the `relayer == 0` branch make this optional by design — when no relayer is set, overpayment is refunded to the user, and an underfunded second leg queues until Gateway `repay`. There is no permanent fund loss.


```solidity
GasLimits memory limits = gasLimits[poolId][scId];
bool hubIsEndpoint = centrifugeId == poolId.centrifugeId() || localCentrifugeId == poolId.centrifugeId();
address refund = hubIsEndpoint || relayer == address(0) ? refundAddress : relayer;
spoke.crosschainTransferShares{value: msg.value}(
   centrifugeId, poolId, scId, receiver, amount, limits.extraGasLimit, limits.remoteExtraGasLimit, refund
);
```


The issue is that this weakens TokenBridge’s stated expectation. The contract’s purpose for spoke → hub → spoke is the relayer-funded second leg, yet `_crosschainTransfer` still accepts those transfers when `relayer == address(0)`. First-leg overpayment is then refunded on the source chain and cannot automatically fund the hub → destination leg, so completion depends on manual `repay` rather than the integrated relayer path.


**Recommended Mitigation:** Document clearly that spoke → spoke without a configured relayer relies on Gateway `repay`, and/or require `relayer != address(0)` (or an explicit user-funded both-legs path) before allowing spoke-to-hub-to-spoke transfers. Deployment should set `TokenBridge.relayer` before enabling those routes if the relayer UX is intended.


**Centrifuge:** Fixed in [centrifuge/protocol-internal#261](https://github.com/centrifuge/protocol-internal/pull/261/changes/3539fb447651b462289577197282685eb249892d)


**BurraSec:** Fix looks good, fallback documented.


### **7.3.2** Directly transferred shares are permanently stuck in `TokenBridge`


**Target:** TokenBridge.sol, ITokenBridge.sol


**Severity:**

- Impact: Low
- Likelihood: Low


**Description:** Because the bridge is Root-endorsed, a normal transfer of restricted shares directly to the bridge may succeed. `FullRestrictions` treats a Root-endorsed recipient as an acceptable target. However, the bridge has no function that can bridge or return a preexisting balance. The protocol’s `TokenRecoverer` can recover assets only by calling recovery functions on a target implementing `IRecoverable`.


**Recommended Mitigation:** Implement the protocol’s standard `Recoverable` mechanism.


**Centrifuge:** Fixed in [centrifuge/protocol-internal#261](https://github.com/centrifuge/protocol-internal/pull/261/changes/6370ec42bcdf66d0213282073d4ac3bc13025cfb)


**BurraSec:** Fix looks good, `TokenBridge` now implements `Recoverable`


6

---

## 7.3.3 Existing-root migration omits the TokenBridge endorsement, disabling `send` for `FullRestrictions` shares

**Target:** FullDeployer.s.sol, MigrationSpell.sol, TokenBridge.sol, FullRestrictions.sol

**Severity:**

- Impact: Medium
- Likelihood: Low

**Description:** `TokenBridge.send` first transfers the user's shares into TokenBridge. Under `FullRestrictions`, TokenBridge must therefore be a member, pool escrow, or Root-endorsed address. Fresh-root deployments endorse it, but existing-root deployments skip that step. `MigrationSpell._missingRootWards` endorses the other required contracts but omits TokenBridge, and its input does not contain the TokenBridge address. As a result, migrated deployments using `FullRestrictions` revert during the initial user-to-bridge transfer, before any cross-chain message is created.

**Recommended Mitigation:** Add TokenBridge to `GlobalParamsInput`, endorse it in the existing-root migration spell, and test `TokenBridge.send` with a `FullRestrictions` share token after migration.

**Centrifuge:** This won't be endorsed, rather added as a member.

**BurraSec:** Acknowledged. The protocol will add `TokenBridge` as a member rather than Root-endorsing it.

7