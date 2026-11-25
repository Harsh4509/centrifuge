![logo: Sherlock wordmark](image)

# **Security Review For**

## <span style="color:#6d57f8">**Centrifuge**</span>


![logo: Centrifuge logo](page_1_image_1_v2.jpg)


**Collaborative Audit Prepared For:** **Centrifuge**
**Lead Security Expert(s):** **[0x52](https://github.com/IAm0x52)**
**[0x73696d616f](https://github.com/0xsimao)**


**Date Audited:** **August 5 - August 15, 2026**


1

---

## **Introduction**

v3.3.0 hardens the pool-management and cross-chain surface introduced across v3.1–v3.2 and makes the protocol's core primitives more flexible. The main additions are a per-pool manifest policy layer that constrains manager actions, fully sovereign per-pool adapter sets, and per-chain risk controls that bound the damage a single compromised chain can do. This release also ships pluggable custom share tokens, a redesigned balance sheet now folded into Spoke, and flexible accounting.

### **Scope**

Repository: centrifuge/protocol-internal

Audited Commit: f0fe9d6ef26df2984f7ab83171dcb6be4d2e6eb1

Final Commit: ac389fbc717660c26c623c5003c35a494929507b

Files:

* src/adapters/HyperlaneAdapter.sol
* src/adapters/StandbyAdapter.sol
* src/admin/GasService.sol
* src/admin/OpsGuardian.sol
* src/admin/ProtocolGuardian.sol
* src/bridge/TokenBridge.sol
* src/core/hub/Accounting.sol
* src/core/hub/Holdings.sol
* src/core/hub/HubHandler.sol
* src/core/hub/HubRegistry.sol
* src/core/hub/Hub.sol
* src/core/hub/ShareClassManager.sol
* src/core/messaging/Gateway.sol
* src/core/messaging/libraries/MessageLib.sol
* src/core/messaging/MessageDispatcher.sol
* src/core/messaging/MessageProcessor.sol
* src/core/messaging/MultiAdapter.sol
* src/core/spoke/PoolEscrow.sol
* src/core/spoke/SnapshotQueue.sol

2

---

* src/core/spoke/SpokeHandler.sol
* src/core/spoke/SpokeRegistry.sol
* src/core/spoke/Spoke.sol
* src/core/utils/BatchedMulticall.sol
* src/core/utils/Envoy.sol
* src/hooks/accounting/NAVManager.sol
* src/hooks/bridge/BridgeCircuitBreaker.sol
* src/managers/adapters/AdapterFailover.sol
* src/managers/hub/Supervisor.sol
* src/policies/hub/StdHubPolicy.sol
* src/token/ShareTokenRegistrar.sol
* src/utils/SubsidyManager.sol
* src/valuations/OracleValuation.sol
* src/vaults/AsyncRequestManager.sol
* src/vaults/BatchRequestManager.sol

## **Final Commit Hash**

<u>**[ac389fbc717660c26c623c5003c35a494929507b](https://github.com/centrifuge/protocol-internal/tree/ac389fbc717660c26c623c5003c35a494929507b)**</u>

## **Findings**

Each issue has an assigned severity:

* High issues are directly exploitable security vulnerabilities that need to be fixed.
* Medium issues are security vulnerabilities that may not be directly exploitable or may require certain conditions in order to be exploited. All major issues should be addressed.
* Low/Info issues are non-exploitable, informational findings that do not pose a security risk or impact the system’s integrity. These issues are typically cosmetic or related to compliance requirements, and are not considered a priority for remediation.

3

---

# Issues Found

<table>
<thead>
<tr><th><span style="color:#f7647c">High</span></th><th><span style="color:#f0b375">Medium</span></th><th><span style="color:#ffecc6">Low/Info</span></th></tr>
</thead>
<tbody>
<tr><td>0</td><td>2</td><td>8</td></tr>
</tbody>
</table>

# Issues Not Fixed and Not Acknowledged

<table>
<thead>
<tr><th><span style="color:#f7647c">High</span></th><th><span style="color:#f0b375">Medium</span></th><th><span style="color:#ffecc6">Low/Info</span></th></tr>
</thead>
<tbody>
<tr><td>0</td><td>0</td><td>0</td></tr>
</tbody>
</table>

4

---

# **Issue M-1: Pool-scoped adapters can claim another pool’s deterministic share-token address [RESOLVED]**

Source:

[https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/35](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/35)


## **Summary**


An attacker who controls one pool’s adapter quorum can submit a `NotifyShareClass` message containing another pool’s salt. The destination Spoke authenticates the message using its outer `poolId`, but it does not verify that the salt belongs to that pool before passing it to the shared `ShareTokenRegistrar`.


The attacker can use the victim’s salt, decimals, metadata, and the official registrar to deploy the victim’s expected token address first. The victim’s legitimate notification then reverts because CREATE2 cannot deploy to the occupied address.


This also breaks the token’s intended cross-network identity. The same address can represent the victim’s share class on one network and an attacker-controlled pool entry on another, creating a credible token-impersonation path for users and integrations that rely on deterministic addresses.


## **Vulnerability Detail**


When a share class is created on the Hub, `ShareClassManager` requires the first eight bytes of its salt to match the share class’s `poolId`. It then records the salt as used:


[ShareClassManager.sol#L35-L57](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/ShareClassManager.sol#L35-L57)


```solidity
PoolId prefixedPoolId = PoolId.wrap(uint64(bytes8(salt)));
require(poolId == prefixedPoolId, InvalidSalt());
require(!salts[salt], AlreadyUsedSalt());
...
salts[salt] = true;
meta.salt = salt;
```


This establishes the intended salt ownership on the Hub. The destination does not repeat that validation.


`NotifyShareClass` carries `poolId`, `scId`, `decimals`, `salt`, and `registrar` as independent fields:


[MessageLib.sol#L373-L383](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/messaging/libraries/MessageLib.sol#L373-L383)


```solidity
struct NotifyShareClass {
    uint64 poolId;
```

5

---

```solidity
    bytes16 scId;
    string name;
    bytes32 symbol;
    uint8 decimals;
    bytes32 salt;
    bytes32 registrar;
    uint128 extraGasLimit;
    bytes payload;
}
```

The transport routes and authenticates the message using `poolId`. It does not check whether `salt` belongs to that pool. After the message reaches `SpokeHandler.addShareClass`, the only registrar check is that its <span style="color:#e6bf7a">address</span> is nonzero. The handler calls the registrar before registering the resulting token:

### [SpokeHandler.sol#L62-L75](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/SpokeHandler.sol#L62-L75)

```solidity
function addShareClass(
    PoolId poolId,
    ShareClassId scId,
    string memory name,
    string memory symbol,
    uint8 decimals,
    bytes32 salt,
    IRegistrar registrar,
    bytes memory payload
) external auth {
    require(address(registrar) != address(0), InvalidRegistrar());

    address shareToken_ = registrar.newToken(name, symbol, decimals, salt, payload);
    spokeRegistry.addShareClass(poolId, scId, shareToken_, registrar);
}
```

The official `ShareTokenRegistrar` deploys tokens with the supplied salt:

### [ShareTokenRegistrar.sol#L112-L127](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/token/ShareTokenRegistrar.sol#L112-L127)

```solidity
function newToken(
    string memory name,
    string memory symbol,
    uint8 decimals,
    bytes32 salt,
    bytes memory
) external auth returns (address) {
    ShareToken token = new ShareToken{salt: salt}(decimals);

    token.file("name", name);
    token.file("symbol", symbol);
    token.rely(root);
```

6

---

```solidity
    return <span style="color:#e6bf7a">address</span>(token);
}
```

The resulting address depends on the registrar address, salt, token creation code, and decimals. Neither `poolId` nor `scId` participates in the derivation:

[ShareTokenRegistrar.sol#L193-L210](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/token/ShareTokenRegistrar.sol#L193-L210)

```solidity
<span style="color:#e6bf7a">bytes32</span> <span style="color:#e06b75">hash</span> = <span style="color:#e6bf7a">keccak256</span>(
    abi.encodePacked(
        bytes1(0xff),
        <span style="color:#e6bf7a">address</span>(this),
        salt,
        <span style="color:#e6bf7a">keccak256</span>(abi.encodePacked(type(ShareToken).creationCode,
            abi.encode(decimals)))
    )
);
```

The protocol's deployment scripts place `ShareTokenRegistrar` at a deterministic address using CREATE3:

[FullDeployer.s.sol#L308-L314](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/script/FullDeployer.s.sol#L308-L314)

```solidity
shareTokenRegistrar = ShareTokenRegistrar(
    create3(
        createSalt("shareTokenRegistrar", V3_3),
        abi.encodePacked(type(ShareTokenRegistrar).creationCode, abi.encode(root,
            batcher))
    )
);
```

The deployment scripts use the same mainnet deployer and suffix across networks. As a result, the registrar and the tokens it deploys can have the same addresses on each supported network. Reusing a share class's salt and decimals therefore produces its expected cross-network token address.

An attacker can exploit this as follows:

1. A victim creates a share class on the Hub. Its salt, decimals, name, and symbol become public before or while its notification is delivered to another chain.
2. The attacker controls a separate pool and its adapter quorum on the destination chain.
3. The attacker submits a `NotifyShareClass` message routed under the attacker's `poolId`, but supplies the victim's salt, decimals, metadata, and the official `ShareTokenRegistrar`.
4. `SpokeHandler` calls the official registrar, which deploys an official `ShareToken` at the address reserved for the victim's share class.

7

---

5. `SpokeRegistry` records that address under the attacker's `(poolId, scId)`:

[SpokeRegistry.sol#L85-L101](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/SpokeRegistry.sol#L85-L101)

```solidity
require(tokenDetails[shareToken_].poolId.isNull(), TokenAlreadyRegistered());

shareClass_.shareToken = IERC20(shareToken_);
shareClass_.registrar = registrar_;
tokenDetails[shareToken_] = TokenDetails(poolId, scId);
```

6. When the victim's legitimate notification arrives, the registrar attempts the same CREATE2 deployment and reverts because the address already contains code.

The attacker can also grant themselves the Spoke manager role for their pool through a forged `UpdateManager` message:

[MessageProcessor.sol#L210-L222](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/messaging/MessageProcessor.sol#L210-L222)

```solidity
if (managerKind == ManagerKind.Spoke) {
    spokeHandler.updateManager(poolId, who, m.canManage);
}
```

Once authorized as a manager, the attacker can issue balances of the predeployed token through `Spoke.issue`:

[Spoke.sol#L231-L239](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/Spoke.sol#L231-L239)

```solidity
function issue(PoolId poolId, ShareClassId scId, address to, uint128 shares)
    external
    payable
    enforced(poolId)
{
    (IERC20 token, IRegistrar registrar) =
        spokeRegistry.shareTokenAndRegistrar(poolId, scId);

    snapshotQueue.queueShares(poolId, scId, shares, true);
    registrar.mint(address(token), to, shares);
}
```

The attacker does not need to authenticate as the victim's pool. Authentication under the attacker's pool is enough because the salt reaches a shared CREATE2 namespace without being rebound to the authenticated `poolId`.

## Impact

The victim's share class cannot be deployed on the affected Spoke through the normal notification flow. Its committed salt resolves to an address that already contains code, causing every legitimate deployment attempt to revert.

8

---

The collision also breaks the intended cross-network identity of the share token. On unaffected networks, the deterministic address represents the victim’s share class. On the affected network, the same address can be registered under the attacker’s pool, display the victim’s name and symbol, and contain balances issued through the protocol’s own Spoke and registrar.


Wallets, token lists, frontends, bridges, and other integrations that copy address allowlists across networks or treat the deterministic address as sufficient proof of identity may display or accept those balances as the victim’s shares.


This creates a token-impersonation path and may cause users or integrations to accept balances that are not shares of the victim’s pool. Recovery requires privileged intervention or a different deployment scheme. Reassigning the occupied token to the victim is unsafe if the attacker has already issued balances or changed its local configuration.


## **Code Snippet**


[ShareClassManager.sol#L35-L57](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/ShareClassManager.sol#L35-L57)

[SpokeHandler.sol#L62-L75](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/SpokeHandler.sol#L62-L75)

[ShareTokenRegistrar.sol#L112-L127](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/token/ShareTokenRegistrar.sol#L112-L127)

[ShareTokenRegistrar.sol#L193-L210](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/token/ShareTokenRegistrar.sol#L193-L210)

[SpokeRegistry.sol#L85-L101](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/SpokeRegistry.sol#L85-L101)


## **Tool Used**


Manual Review


## **Recommendation**


Validate the salt’s pool prefix in `SpokeHandler.addShareClass` before calling the registrar:


```text
PoolId saltPoolId = PoolId.wrap(uint64(bytes8(salt)));
<span style="color:#e6bf7a">require</span>(saltPoolId == poolId, InvalidSalt());
```


## **Discussion**


**hieronx**


Fixed in [https://github.com/centrifuge/protocol-internal/pull/351](https://github.com/centrifuge/protocol-internal/pull/351)

9

---

# Issue M-2: A frozen investor is able to extract escrowed shares via the shares claim paths [RESOLVED]

Source:
[https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/37](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/37)

## Summary

Shares leave the pool escrow through [Spoke::withdrawShares()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/Spoke.sol#L256-L266), which leads to `from = poolEscrow` and `to = receiver` and the controller is never checked, so a frozen investor is able to extract its escrowed shares.

## Vulnerability Detail

`AsyncVault::deposit()` does `shares = asyncManager.deposit(this, assets, receiver, controller);`, and following the call path never checks for `_canTransfer()`.

However, [AsyncRequestManager::maxDeposit()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L519-L524) and [AsyncRequestManager::maxMint()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L532-L535) both call [AsyncRequestManager::_canTransfer()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L657-L659) on exactly the escrow to controller edge and return 0 for a frozen controller, and [AsyncRequestManager::_processRedeem()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L419-L453) and [AsyncRequestManager::claimCancelDepositRequest()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L460-L492) require the controller to pass that same check before releasing assets.

## Impact

A frozen investor extracts their whole `maxMint` and `claimableCancelRedeemRequest` to an address they pick: any non frozen one under [FreezeOnly::checkERC20Transfer()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/token/hooks/FreezeOnly.sol#L31-L40) and [RedemptionRestrictions::checkERC20Transfer()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/token/hooks/RedemptionRestrictions.sol#L30-L47) or any member address under [FullRestrictions::checkERC20Transfer().](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/token/hooks/FullRestrictions.sol#L31-L56) An expired memberlist entry escapes the same way, while [AsyncRequestManager::maxMint()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L532-L535) reports 0 to every ERC-4626 integrator.

## Code Snippet

[AsyncRequestManager::_processDeposit()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L379-L383), which delegates the restriction checks to the share transfer:

```
// NOTE: Assumes restrictions check of receiver to be done in the share transfer
spoke.withdrawShares(vaultDetails.poolId, vaultDetails.scId, receiver, sharesDown);
```

Against [AsyncRequestManager::_processRedeem()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L427-L433), which does check the controller:

```
if (controller != receiver) {
    require(
```

10

---

```solidity
        _canTransfer(vault_, controller, receiver, convertToShares(vault_,
         →  assetsDown)), TransferNotAllowed()
    );
}
```

## Tool Used

Manual Review

## Recommendation


Require [AsyncRequestManager::_canTransfer()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L657-L659) on the escrow to controller edge in [AsyncRequestManager::_processDeposit()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L368-L384) and [AsyncRequestManager::claimCancelRedeemRequest()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L495-L512), just like [AsyncRequestManager::maxMint().](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L532-L535)

## Discussion

**hieronx**


Fixed in [https://github.com/centrifuge/protocol-internal/pull/360](https://github.com/centrifuge/protocol-internal/pull/360)


11

---

# **Issue L-1: `StandbyAdapter` does not account for its additional execution cost and EIP-150 gas reduction [RESOLVED]**


Source:
[https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/36](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/36)


## **Summary**


`StandbyAdapter.forward` passes the original `gasLimit` to the underlying adapter without accounting for the additional `StandbyAdapter.handle` execution layer. A normal delivery follows `Adapter → MultiAdapter`, while a standby delivery follows `Adapter → StandbyAdapter → MultiAdapter`.


The standby path adds approximately 3,000 to 4,000 gas of execution cost based on testing, along with another EIP-150 63/64 gas reduction when `StandbyAdapter` calls `MultiAdapter`. For a message requiring 100,000 gas, the additional EIP-150 boundary removes roughly 1,563 gas. Combined with the wrapper’s execution cost, `MultiAdapter` may receive around 4.5% to 5.5% less gas than expected.


This can cause a standby delivery to run out of gas even though the same `gasLimit` is sufficient through a normal adapter. Since the standby adapter is intended to restore liveness when another adapter is unavailable, underfunding this path can prevent it from supplying the missing quorum vote.


## **Code Snippet**


[StandbyAdapter.sol#L62-L71](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/adapters/StandbyAdapter.sol#L62-L71)

[StandbyAdapter.sol#L80-L88](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/adapters/StandbyAdapter.sol#L80-L88)


## **Tool Used**


Manual Review


## **Recommendation**


Increase the gas limit passed to `underlying.estimate` and `underlying.send` by a fixed reserve for the execution cost of `StandbyAdapter.handle`, then scale it to compensate for the additional EIP-150 boundary.


For example:


12

---

```text
uint256 adjustedGasLimit =
    Math.ceilDiv((gasLimit + STANDBY_RECEIVE_COST) * 64, 63);
```

## Discussion

**hieronx**

Fixed in [https://github.com/centrifuge/protocol-internal/pull/351](https://github.com/centrifuge/protocol-internal/pull/351)

13

---

# Issue L-2: SyncDepositVault calls its ERC-4626 conversion views from the async redeem manager, which is wrong on a sync vault [ACKNOWLEDGED]

Source:

[https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/38](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/38)

This issue has been acknowledged by the team but won't be fixed at this time.

## Summary


[SyncDepositVault](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncDepositVault.sol#L21-L34) passes the async redeem manager into <u>BaseVault</u> as [BaseVault::baseManager](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L30), so the four conversion views quote the registry share price, while the deposit uses [SyncManager::pricePoolPerShare()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L199-L207), returning the pool's configured valuation instead.

## Vulnerability Detail

[BaseVault](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L25-L79)::totalAssets()</u>, [BaseVault::convertToShares()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L173-L175), [BaseVault::convertToAssets()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L180-L182) and [BaseVault::pricePerShare()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L189-L191) are not virtual, so they land in [AsyncRequestManager::convertToShares()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L585-L603) and [AsyncRequestManager::convertToAssets()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L606-L624), which read [SpokeRegistry::pricePoolPerShare()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/SpokeRegistry.sol#L380-L385).

[BaseSyncDepositVault::deposit()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L374-L380) and [BaseSyncDepositVault::previewDeposit()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L369-L371) instead reach [SyncManager::convertToShares()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L172-L191), and [BaseSyncDepositVault::mint()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L393-L398) and [BaseSyncDepositVault::previewMint()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L388-L390) reach [SyncManager::_shareToAssetAmount():](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L251-L274)

```
if (address(valuation_) == address(0)) {
    price = spokeRegistry.pricePoolPerShare(poolId, scId, true);
} else {
    price = valuation_.pricePoolPerShare(poolId, scId);
}
```

## Impact

An integrator calling [BaseVault::convertToShares()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L173-L175), or an accounting system valuing a position from [BaseVault::pricePerShare()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L189-L191), get the spoke registry price while the deposit executes at the valuation price.

## Code Snippet

[SyncDepositVault:](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncDepositVault.sol#L21-L34)

14

---

```text
BaseVault(poolId_, scId_, asset_, token_, root_,
 →  IBaseRequestManager(address(asyncRedeemManager_)))
[BaseSyncDepositVault](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L352-L404)(syncDepositManager_)
BaseAsyncRedeemVault(asyncRedeemManager_)
```

## **Tool Used**

Manual Review

## **Recommendation**

Make the four views virtual on [BaseVault](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L25-L79) and override them in <u>BaseSyncDepositVault</u> to price through [BaseSyncDepositVault::syncDepositManager.](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L353)

## **Discussion**

**hieronx**

Acknowledged but since it predates this release, don't think it's worth fixing. We will do a full vault redesign soon and will address it there.

15

---

# **Issue L-3:** `Supervisor::_checkNotSelfRemoval()` **re-verts on a malformed targed instead of returning [ACKNOWLEDGED]**



Source:

[https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/39](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/39)


This issue has been acknowledged by the team but won't be fixed at this time.

## **Summary**


[Supervisor::_checkNotSelfRemoval()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L86-L99) casts `managerCall` using [CastLib::toAddress()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/misc/libraries/CastLib.sol#L18-L21), which reverts on any word whose low 12 bytes are non zero, so a sentinel vetoing such an authorization reverts.

## **Vulnerability Detail**


[Supervisor::cancelAuthorization()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L77-L82) calls [Supervisor::_checkNotSelfRemoval()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L86-L99) whenever more than one sentinel is registered. The guard is a chain of early returns: a foreign selector, args under 224 bytes, a short inner payload and a non `RemoveSentinel` payload all return and leave the veto intact. However, the target comparison runs [CastLib::toAddress()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/misc/libraries/CastLib.sol#L18-L21), which reverts for `bytes32` having low non zero 12 bytes.


It's reachable because [StdHubPolicy::_checkManagerCall()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L278-L294) returns `delay` for a remote `centrifugeId` before it casts the target.

## **Impact**


The sentinel set loses its veto over that authorization, and the entry sits in [HubRegistry::authorizedAfter](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/HubRegistry.sol#L34-L34) until a pool manager clears it. [Hub::managerCall()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Hub.sol#L487-L506) does the same, so the authorization is impossible too.

## **Code Snippet**


[Supervisor::_checkNotSelfRemoval()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L95-L97) reverts on a malformed target:


```text
<span style="color:#e6bf7a">if</span> (target.toAddress() != <span style="color:#e6bf7a">address(this)</span>) <span style="color:#e6bf7a">return</span>;
<span style="color:#e6bf7a">if</span> (payload.length < <span style="color:#d19966">64</span>) <span style="color:#e6bf7a">return</span>;
<span style="color:#e6bf7a">if</span> (payload.toUint256(<span style="color:#d19966">0</span>) != <span style="color:#e6bf7a">uint256(uint8(TrustedCall.RemoveSentinel))</span>) <span style="color:#e6bf7a">return</span>;
```


[CastLib::toAddress():](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/misc/libraries/CastLib.sol#L18-L21)


```text
<span style="color:#e6bf7a">require(uint96(uint256(addr))</span> == <span style="color:#d19966">0</span>, PrefixNotZero());
```

16

---

## **Tool Used**

Manual Review

## **Recommendation**

Compare and return early instead.

## **Discussion**

**hieronx**

Acknowledged, no impact.

17

---

# **Issue L-4: `SpokeHandler::executeTransferShares()` only validates the receiver on the destination chain [ACKNOWLEDGED]**


Source: [https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/40](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/40)


This issue has been acknowledged by the team but won't be fixed at this time.


## **Summary**


`receiver` is only checked on the destination chain, after the origin has already burned the shares, so a right alined `bytes32` receiver will keep reverting,


## **Vulnerability Detail**


<u>`[SpokeHandler::executeTransferShares()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/SpokeHandler.sol#L98-L104)`</u> decodes the using <u>`[CastLib::toAddress()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/misc/libraries/CastLib.sol#L18-L21)`</u>, which requires the low 12 bytes to be zero, the form <u>`[CastLib::toBytes32()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/misc/libraries/CastLib.sol#L23-L25)`</u> produces. A right aligned word reverts there with `[CastLib::PrefixNotZero()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/misc/libraries/CastLib.sol#L6-L6)`. However, nothing on the origin checks that.


## **Impact**


The sender loses the whole bridged amount, burned on the origin and unmintable on the destination, with <u>`[HubHandler::initiateTransferShares()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/HubHandler.sol#L117-L155)`</u> having already [moved the issuance](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/HubHandler.sol#L147-L148) to the target chain.


## **Code Snippet**


<u>`[Spoke::crosschainTransferShares()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/Spoke.sol#L319-L321)`</u> burns without checking `receiver`:


```
SafeTransferLib.safeTransferFrom(address(share), owner, address(this), amount);
SafeTransferLib.safeApprove(address(share), address(registrar), amount);
registrar.burn(address(share), address(this), amount);
```


## **Tool Used**


Manual Review


## **Recommendation**


Validate the encoding on the origin.


18

---

# **Discussion**


## **hieronx**


This is infeasible to fix: in the future a bridge transaction might go to a non-EVM spoke. This is listed in out of scope.


19

---

# **Issue L-5: Hub::setAccountMetadata() and Hub::setHoldingAccountId() are unreachable on onchainAccounting pools [RE-SOLVED]**


Source:
[https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/42](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/42)


## **Summary**


[StdHubPolicy::_isAccountingSelector()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L250-L259) includes [Hub::setAccountMetadata()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Hub.sol#L325-L331) and [Hub::setHoldingAccountId()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Hub.sol#L374-L382) and when under [StdHubPolicy::onchainAccounting](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L73) are gated to [NAVManager](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/hooks/accounting/NAVManager.sol#L18), which doesn't implement them.


## **Vulnerability Detail**


Under [StdHubPolicy::onchainAccounting](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L73),</u> an accounting selector [requires](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L180-L184) the caller to be [StdHubPolicy::navManager,](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L60) reverting otherwise. <u>NAVManager</u> calls <u>Hub</u> only to [create accounts,](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/hooks/accounting/NAVManager.sol#L109-L112) [initialize a holding,](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/hooks/accounting/NAVManager.sol#L147-L148) [update its value and valuation](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/hooks/accounting/NAVManager.sol#L196-L201) and [add a journal,](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/hooks/accounting/NAVManager.sol#L235) so the other two selectors have no in-policy caller.


However, they are still reachable through the [Hub](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Hub.sol#L41),</u> since [Accounting::setAccountMetadata()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Accounting.sol#L79-L83) and [Holdings::setAccountId()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Holdings.sol#L65-L74) are auth, so they can still be called through other ways.


## **Impact**


On a pool with <u>Std[Hub](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Hub.sol#L41)Policy::onchainAccounting,</u> account metadata cannot be set and a holding's account ids cannot be repointed except by another auth authority.


## **Code Snippet**


[StdHubPolicy::_authorizationDelay()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L180-L184)


```
<span style="color:#e6bf7a">if</span> (_isAccountingSelector(selector)) {
    <span style="color:#e6bf7a">require(caller</span> == [navManager](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/hooks/accounting/NAVManager.sol#L18), OnchainAccountingOnly());
    <span style="color:#e6bf7a">return</span> <span style="color:#d19966">0;</span>
}
```


[StdHubPolicy::_isAccountingSelector()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L250-L259)


## **Tool Used**


Manual Review


20

---

## Recommendation

Document in [StdHubPolicy::_isAccountingSelector()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L250-L259) that [Hub::setAccountMetadata()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Hub.sol#L325-L331) and [Hub::setHoldingAccountId()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Hub.sol#L374-L382) are intentionally frozen under [StdHubPolicy::onchainAccounting](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L73) and reachable only through another `auth`.

## Discussion

### **hieronx**

`setAccountMetadata` is fixed in [https://github.com/centrifuge/protocol-internal/pull/328](https://github.com/centrifuge/protocol-internal/pull/328)

`setHoldingAccountId` is intentionally not exposed.

21

---

# **Issue L-6:** `[Supervisor::cancelAuthorization()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L77-L82)` **skips its guard at one sentinel, which also means the last sentinel can veto its removal forever [RESOLVED]**

Source:
[https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/45](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/45)

## **Summary**

[Supervisor::fromHub()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L48-L70) can't remove the last sentinel, so a pool holding one has to add a second first, which is an out of policy `managerCall` that goes through a timelock, and [Supervisor](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L20-L23)::cancelAuthorization()</u> can be called repeatedly so the sentinel stays there forever.

## **Vulnerability Detail**

The removal branch of [Supervisor::fromHub()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L48-L70) requires [Supervisor::sentinelCount](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L29-L29) above one. The add is reachable only through [Hub::managerCall()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Hub.sol#L486-L506), and [StdHubPolicy::_checkManagerCall()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L278-L294) doesn't check for the <u>Supervisor</u>, so it goes through a `delay`.

The cancel has no delay as seen in [StdHubPolicy::_authorizationDelay()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/policies/hub/StdHubPolicy.sol#L218-L220) and [HubRegistry::cancelAuthorization()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/HubRegistry.sol#L154-L161) deletes the attempt.

## **Impact**

A pool with one sentinel cannot replace it, unless [Hub::setPolicy()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/hub/Hub.sol#L103-L108) is called by a `ward`.

## **Code Snippet**

[Supervisor::cancelAuthorization()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L77-L82) always leaves at least 1 sentinel.

```solidity
function cancelAuthorization(bytes calldata data) external onlySentinel {
    if (sentinelCount > 1) {
        _checkNotSelfRemoval(data, msg.sender);
    }
    hub.cancelAuthorization(poolId, data);
}
```

[Supervisor::fromHub()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/managers/hub/Supervisor.sol#L62-L64) doesn't allow removing the last sentinel.

```solidity
require(sentinels[sentinel], NotSentinel());
require(sentinelCount > 1, LastSentinel());
```

22

---

## **Tool Used**


Manual Review


## **Recommendation**


Document this behaviour and explain the recovery.


## **Discussion**


**hieronx**


Agree we should document this.

23

---

# **Issue L-7:** `SyncManager::maxDeposit()` **and** `SyncManager::maxMint()` **revert with** `InvalidPrice` **while a price is still unset, instead of returning 0 [ACKNOWL-EDGED]**


Source:
[https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/46](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/46)


This issue has been acknowledged by the team but won't be fixed at this time.


## **Summary**


[SyncManager::maxDeposit()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L160-L169) and [SyncManager::maxMint()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L151-L157) call [SpokeRegistry::pricePoolPerAsset()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/SpokeRegistry.sol#L388-L397) which reverts with `InvalidPrice` while `computedAt` is 0, but [IERC7575](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/misc/interfaces/IERC7575.sol#L67-L75) requires these views to never revert.


## **Vulnerability Detail**


[SyncManager::maxDeposit()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L229-L249) computes the reserve headroom with [SyncManager::_maxDeposit()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L160-L169), returning 0 for an unlinked vault, then calls [SyncManager::_maxAssetsAndShares()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L284-L294), which reverts if `pricePoolPerAsset` or `pricePoolPerShare` are not valid.


## **Impact**


[BaseSyncDepositVault::maxDeposit()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L364-L366) and [BaseSyncDepositVault::maxMint()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/BaseVaults.sol#L383-L385) revert instead of following the ERC-4626 and ERC-7575 specification.


## **Code Snippet**


[SyncManager::_maxConvertibleAssets()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L303-L307), reached before `maxAssets` is looked at:


```text
D18 poolPerShare = pricePoolPerShare(vaultDetails.poolId, vaultDetails.scId);
D18 poolPerAsset =
    spokeRegistry.pricePoolPerAsset(vaultDetails.poolId, vaultDetails.scId,
     ↪  vaultDetails.assetId, true);

if (poolPerShare.isZero() || poolPerAsset.isZero()) return 0;
```


[SpokeRegistry::pricePoolPerAsset():](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/core/spoke/SpokeRegistry.sol#L393-L394)


```text
Price memory poolPerAsset = _pricePoolPerAsset[poolId][scId][assetId];
require(!checkValidity || poolPerAsset.isValid(), InvalidPrice());
```


24

---

# Tool Used


Manual Review


# Recommendation


Use `checkValidity = false` inside [SyncManager::_maxConvertibleAssets(),](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L298-L315) [SyncManager::convertToShares()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L172-L191) and [SyncManager::_shareToAssetAmount(),](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L251-L274) just like [AsyncRequestManager::convertToShares(),](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/AsyncRequestManager.sol#L585-L604) but make sure to keep the revert in [SyncManager::deposit()](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/blob/main/protocol-internal/src/vaults/SyncManager.sol#L125-L134) and the state changing functions.


# Discussion


### **hieronx**


Acknowledged but since it predates this release, don't think it's worth fixing. We will do a full vault redesign soon and will address it there.


25

---

# **Issue L-8: Protocol deployment scripts do not use the scoped `DeployGate` revision [RESOLVED]**

Source:
[https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/50](https://github.com/sherlock-audit/2026-08-centrifuge-august-5th-2026/issues/50)

## **Summary**

The scoped `create3-gate` revision is `41e0f70`, but `protocol-internal` pins its `lib/create3-gate` submodule to the older ancestor `0665d63`. Because the protocol remaps `create3-gate/` imports to this submodule, `GatedDeployer` compiles against the older gate and deploys it at `0xBA08f1fD092031C81296fC59f6539b21b38f2249`, rather than deploying the scoped gate at `0xac9C69450016396F0A00648aBA4488433f958E12`. The gate address is also part of every downstream CREATE3 address derivation, so the production deployment generated by the current scripts will not correspond to the scoped gate revision or its derived addresses.

## **Vulnerability Detail**

## **Impact**

## **Code Snippet**

The protocol redirects `create3-gate/` imports to its pinned submodule:

[remappings.txt#L15-L16](https://github.com/sherlock-audit2/2026-08-centrifuge-v3-3-update-aug-26th-2026/blob/main/protocol-internal/remappings.txt#L15-L16)

```text
create3-gate/=lib/create3-gate/
```

`GatedDeployer` consequently imports its gate address from that dependency:

[GatedDeployer.s.sol#L8-L13](https://github.com/sherlock-audit2/2026-08-centrifuge-v3-3-update-aug-26th-2026/blob/main/protocol-internal/script/deploy/GatedDeployer.s.sol#L8-L13)

```solidity
<span style="color:#e6bf7a">import</span> {DEPLOY_GATE_ADDRESS} from <span style="color:#99c278">"create3-gate/script/DeployGate.d.sol";</span>
```

The pinned `0665d63` dependency uses `0xBA08...`:

[DeployGate.d.sol@0665d63#L9-L14](https://github.com/centrifuge/create3-gate/blob/0665d63f27673c2b5b9ab2008c49ff9404d41b12/script/DeployGate.d.sol#L9-L14)

```solidity
<span style="color:#e6bf7a">address</span> <span style="color:#e06b75">constant</span> DEPLOY_GATE_ADDRESS = <span style="color:#d19966">0xBA08f1fD092031C81296fC59f6539b21b38f2249;</span>
```

The scoped `41e0f70` revision instead uses `0xac9C...`:

[DeployGate.d.sol@41e0f70#L9-L14](https://github.com/centrifuge/create3-gate/blob/41e0f70db52f9f06747942625cf5b74f03184c8d/script/DeployGate.d.sol#L9-L14)

```solidity
<span style="color:#e6bf7a">address</span> <span style="color:#e06b75">constant</span> DEPLOY_GATE_ADDRESS = <span style="color:#d19966">0xac9C69450016396F0A00648aBA4488433f958E12;</span>
```

26

---

## **Tool Used**


Manual Review


## **Recommendation**


Update the `protocol-internal/lib/create3-gate` submodule to `41e0f70`


27

---

# **Disclaimers**


Sherlock does not provide guarantees nor warranties relating to the security of the project.


Usage of all smart contract software is at the respective users’ sole risk and is the users’ responsibility.


28