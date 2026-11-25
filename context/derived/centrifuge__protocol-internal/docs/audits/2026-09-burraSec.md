![logo: Burra Sec wordmark](page_1_image_1_v2.jpg)


# **Centrifuge September Updates Audit Report**


Prepared by [Burra Security](https://www.burrasec.com/)
Version 1.0


## **Researchers**


fuzious


Taridoku


Alex Filippov


October 21, 2026

---

## Contents

<table><tr><td>1</td><td>About Burra Security</td><td>2</td></tr><tr><td>2</td><td>Disclaimer</td><td>2</td></tr><tr><td>3</td><td>Risk Classification</td><td>2</td></tr><tr><td>4</td><td>Protocol Summary</td><td>2</td></tr><tr><td>5</td><td>Audit Scope</td><td>2</td></tr><tr><td>6</td><td>Executive Summary</td><td>3</td></tr><tr><td>7</td><td>Findings</td><td>4</td></tr><tr><td>7.1</td><td>Medium Risk</td><td>4</td></tr><tr><td></td><td>7.1.1 OpsGuardian can permanently poison Hub asset registrations</td><td>4</td></tr><tr><td>7.2</td><td>Low Risk</td><td>5</td></tr><tr><td></td><td>7.2.1 Anyone can permanently bind an asset to 0 decimals by registering it before its decimals are set</td><td>5</td></tr></table>

1

---

## 1 About Burra Security

Burra Security offers security auditing and advisory services with a special focus on cross-chain and interoperability protocols and their integrations. Learn about us at [burrasec.com.](https://www.burrasec.com/)

## 2 Disclaimer

A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource, and expertise-bound effort where we try to find as many vulnerabilities as possible. We can not guarantee 100% security after the review or even if the review will find any vulnerabilities. Subsequent security reviews, bug bounty programs, and on-chain monitoring are recommended.

## 3 Risk Classification

<table>
<thead>
<tr><th></th><th><b>Impact: High</b></th><th><b>Impact: Medium</b></th><th><b>Impact: Low</b></th></tr>
</thead>
<tbody>
<tr><td><b><b>Likelihood: High</b></b></td><td>Critical</td><td>High</td><td>Medium</td></tr>
<tr><td><b><b>Likelihood: Medium</b></b></td><td>High</td><td>Medium</td><td>Low</td></tr>
<tr><td><b><b>Likelihood: Low</b></b></td><td>Medium</td><td>Low</td><td>Low</td></tr>
</tbody>
</table>

## 4 Protocol Summary

The audited changes target Centrifuge's cross-chain messaging layer, its gas pricing, and the Hub and Spoke contracts that manage tokenized pools across networks.

The Gateway now reads message framing (length, pool ID, source chain) from the MessageProcessor rather than the ops-filed GasService. The GasService prices each adapter's receive path through the new `IAdapter-GasService.receiveCost`, which the Axelar, Chainlink, Hyperlane, LayerZero and Standby adapters reach via `MultiAdapter.messageGas()`. The ChainlinkAdapter adopts CCIP 2.0 `GenericExtraArgsV3`, letting a lane request faster-than-finality delivery.

On the Hub, `unauthorizeSpokeCall` routes through the StdHubPolicy pool policy, and the ShareClassManager and Holdings counters widen to `uint256`. On the Spoke, PoolEscrow becomes Escrow, absorbing the misc escrow base, and the transfer hooks no longer block memberlist updates for pool escrows.

## 5 Audit Scope

The scope of the audit is the following diffs:

- the diff between commit `58e0ddfe0af7e5c683e56228885a6aabedadff6c` and commit `976315f1bece07e1d3559313933166d2561dd93e` (PR #387)
- the diff between commit `1b0e3f1d36d2b37d0d90669f703c415c7845a95e` and commit `730ed753e4a4b704f03e40c46373e6d58f8ff6ea` (PR #398)
- the diff between commit `c818db95ba47861da85028ab8a4c3d5874155592` and commit `7fbcc524d6f0b33d9d85d7160d9c078b43f7cf72` (PR #399)
- the diff between commit `7fbcc524d6f0b33d9d85d7160d9c078b43f7cf72` and commit `2738072e7d0d8ca90b6726151358e47fcf0486c6` (PR #408)
- the diff between commit `b56d13c9ba2944887c4fe18ca5ce49e70859a138` and commit `c818db95ba47861da85028ab8a4c3d5874155592` (PR #410)

2

---

- the diff between commit `2738072e7d0d8ca90b6726151358e47fcf0486c6` and commit `abcdc4e85b34c54ef9c78189b865d9f10e9194bb` (PR #415)
- the diff between commit `81d1cff07062f44000f2924009b450b571896414` and commit `[e1cac8ca96ef](https://github.com/centrifuge/protocol-internal/blob/e1cac8ca96efc34a6f3cb0a7f565b9adccc46780)c34a6f3cb0a7f565b9adccc46780` (PR #422)

for all the files in:

```
src/**
```

## 6 Executive Summary

Over the course of 2 days, the Burra Security team conducted an audit on the <span style="color:#1f7fc7">[Centrifuge September Updates](https://github.com/centrifuge/protocol-internal)</span> smart contracts provided by <span style="color:#1f7fc7">[Centrifuge](https://centrifuge.io/)</span>. In this period, a total of 2 issues were found.

### Summary

<table>
<tr><td>Project Name</td><td>[Centrifuge September Updates](https://github.com/centrifuge/protocol-internal)</td></tr>
<tr><td>Repository</td><td><span style="color:#2580c3">[protocol-internal](https://github.com/centrifuge/protocol-internal)</span></td></tr>
<tr><td>Commit</td><td><span style="color:#2580c3">[e1cac8ca96ef](https://github.com/centrifuge/protocol-internal/blob/e1cac8ca96efc34a6f3cb0a7f565b9adccc46780). . .</span></td></tr>
<tr><td>Fix Commit</td><td><span style="color:#2580c3">[051718ed55e3](https://github.com/centrifuge/protocol-internal/blob/051718ed55e3db59ed713596441e1dc837b8d461). . .</span></td></tr>
<tr><td>Audit Timeline</td><td>23rd September - 24th September</td></tr>
<tr><td>Methods</td><td>Manual Review</td></tr>
</table>

### Issues Found

<table>
<tr><td>Critical Risk</td><td>0</td></tr>
<tr><td>High Risk</td><td>0</td></tr>
<tr><td>Medium Risk</td><td>1</td></tr>
<tr><td>Low Risk</td><td>1</td></tr>
<tr><td>Informational</td><td>0</td></tr>
<tr><td>Gas Optimizations</td><td>0</td></tr>
<tr><td>Total Issues</td><td>2</td></tr>
</table>

### Summary of Findings

<table>
<tr><td>[M-1] OpsGuardian can permanently poison Hub asset registrations</td><td>Resolved</td></tr>
<tr><td>[L-1] Anyone can permanently bind an asset to 0 decimals by registering it<br />before its decimals are set</td><td>Resolved</td></tr>
</table>

3

---

# 7 Findings

## 7.1 Medium Risk

### 7.1.1 `OpsGuardian` **can permanently poison Hub asset registrations**

**Target:** [OpsGuardian.sol#L67-L73,](https://github.com/centrifuge/protocol-internal/blob/abcdc4e85b34c54ef9c78189b865d9f10e9194bb/src/admin/OpsGuardian.sol#L67-L73) [MultiAdapter.sol#L87-L108,](https://github.com/centrifuge/protocol-internal/blob/abcdc4e85b34c54ef9c78189b865d9f10e9194bb/src/core/messaging/MultiAdapter.sol#L87-L108) [SpokeRegistry.sol#L304-L317,](https://github.com/centrifuge/protocol-internal/blob/abcdc4e85b34c54ef9c78189b865d9f10e9194bb/src/core/spoke/SpokeRegistry.sol#L304-L317) <span style="color:#2580c3">[MessageProcessor.sol#L102-L106,](https://github.com/centrifuge/protocol-internal/blob/abcdc4e85b34c54ef9c78189b865d9f10e9194bb/src/core/messaging/MessageProcessor.sol#L102-L106) [HubRegistry.sol#L47-L54](https://github.com/centrifuge/protocol-internal/blob/abcdc4e85b34c54ef9c78189b865d9f10e9194bb/src/core/hub/HubRegistry.sol#L47-L54)</span>

**Severity:**

- Impact: High
- Likelihood: Low

**Description:** `OpsGuardian.setAdapters` lets the ops Safe replace an existing global adapter set with arbitrary adapter addresses. A compromised ops Safe can therefore install its own adapter and submit a forged `RegisterAsset` message from the remote chain. A one-adapter set with a threshold of one can call `MultiAdapter.handle` directly, so no real cross-chain delivery or adapter wiring is required.

Asset IDs are predictable because `SpokeRegistry` assigns them using an incrementing counter. The attacker can pre-register the next asset ID on the Hub with incorrect decimals. When the real asset is registered, `HubRegistry.registerAsset` reverts with `AssetAlreadyRegistered`.

`HubRegistry` has no function to update or remove an asset registration, so even Root cannot correct the entry. The asset can never be registered with its real metadata and cannot be used safely on that Hub. Replacing the adapter set or revoking the ops Safe does not recover it. Because several core contracts hold the `HubRegistry` address as an immutable dependency, recovery requires replacing core contracts.

**Recommended Mitigation:** Consider allowing `OpsGuardian` to set a chain's global adapters only while `activeSessionId` is 0.

**Centrifuge:** Fixed in [centrifuge/protocol-internal#425.](https://github.com/centrifuge/protocol-internal/pull/425/changes/9dcfbf3f58858b1640b79c4941fb6eb8ecd23497)

**BurraSec:** Fix looks good.

4

---

## 7.2 Low Risk

### 7.2.1 Anyone can permanently bind an asset to 0 decimals by registering it before its decimals are set

**Target:** [Spoke.sol#L84-L113,](https://github.com/centrifuge/protocol-internal/blob/abcdc4e85b34c54ef9c78189b865d9f10e9194bb/src/core/spoke/Spoke.sol#L84-L113) [SpokeRegistry.sol#L303-L318,](https://github.com/centrifuge/protocol-internal/blob/abcdc4e85b34c54ef9c78189b865d9f10e9194bb/src/core/spoke/SpokeRegistry.sol#L303-L318) [HubRegistry.sol#L47-L55](https://github.com/centrifuge/protocol-internal/blob/abcdc4e85b34c54ef9c78189b865d9f10e9194bb/src/core/hub/HubRegistry.sol#L47-L55)

**Severity:**

- Impact: Medium
- Likelihood: Low

**Description:** `Spoke.registerAsset` is permissionless and reads the asset's decimals at call time. Some tokens report 0 decimals until their issuer finishes setting them up:

- An OpenZeppelin `ERC6909Metadata` ID the issuer has not created yet returns 0 decimals and empty strings rather than reverting.
- Circle's `FiatToken`, used by USDC, EURC and the Bridged USDC Standard, keeps `decimals` in [storage.](https://github.com/circlefin/stablecoin-evm/blob/fc85788bc7c23cefe3df1a757133048bfddadeaa/contracts/v1/FiatTokenV1.sol#L36) Its [proxy](https://github.com/circlefin/stablecoin-evm/blob/fc85788bc7c23cefe3df1a757133048bfddadeaa/contracts/v1/FiatTokenProxy.sol#L30-L33) takes no initialization data, and Circle's [deploy script](https://github.com/circlefin/stablecoin-evm/blob/fc85788bc7c23cefe3df1a757133048bfddadeaa/scripts/deploy/deploy-fiat-token.s.sol#L101-L119) calls `initialize` in a later transaction. An attacker can submit the registration between the proxy deployment and its initialization.

An attacker who registers such a token first binds it to an asset ID in `SpokeRegistry`, and the destination `HubRegistry` stores 0 decimals for that ID. Registering the token again later resends the same ID, which the Hub rejects with `AssetAlreadyRegistered`. `HubRegistry` has no way to correct the entry, even for Root. The Hub values holdings with the stored decimals, so a 6-decimal asset would be overvalued by 10^6, and the asset can never be used on that Hub.

This is a regression in v3.3. Before [47c9467,](https://github.com/centrifuge/protocol-internal/commit/47c946721785d83845432bdf9930ab15cbee1686) `Spoke.registerAsset` rejected fewer than 2 decimals and `HubRegistry` treated 0 decimals as unregistered. The out-of-scope item on mutable decimals makes a bad registration "the registering pool's error", but here a third party registers the token before its decimals are final, and the pool can neither prevent nor undo it. The DoS is permanent, and fixing it requires redeploying `HubRegistry` together with the core contracts that hold it as an immutable dependency.

**Recommended Mitigation:** Consider adding a Root-only way to correct asset decimals in `HubRegistry`.

**Centrifuge:** Fixed in [centrifuge/protocol-internal#425.](https://github.com/centrifuge/protocol-internal/pull/425/changes/9dcfbf3f58858b1640b79c4941fb6eb8ecd23497)

**BurraSec:** Fix looks good.

5