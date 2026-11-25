# Centrifuge:
Protocol v3


## <span style="color:#2a6099">security review</span>


**reviewed by:**


**<span style="color:#2a6099">xmxanuel</span>**
[cantina.xyz/u/xmxanuel](https://cantina.xyz/u/xmxanuel)

4<sup>th</sup> April 2025

---

## 1. Executive Summary


The Centrifuge team has asked xmxanuel to review their Solidity codebase for `<u>protocol v3</u>` as security reviewer to give feedback on overall design and to identify security vulnerability.


The review began with version `2b657c3de80b2f1153ce64403209f2c8cb8527ac`. However, during the review, a new version was provided, which included additional features. The second version has the following commitHash `<u>adea6c40869e529210005361d54add16507b108f</u>`


The following report only includes findings related to security and not the overall design feedback. Since the protocol has still been under the development some additional `<u>high</u>` findings turned out to be known issues or under development which could be verified by additional provided documentation and are not included in the report.

Page 1 of 8

---

## 2. Disclaimer


This security review report is provided "as is" and for informational purposes only. The purpose of this report is to assist the client in identifying potential security vulnerabilities in the reviewed code, based on the scope and methodology agreed upon. It does not constitute legal, investment, financial, or any other form of professional advice.


No warranties or guarantees are made regarding the completeness, accuracy, or security of the reviewed code. The author and any affiliated parties make no representations or warranties, express or implied, and expressly disclaim any liability or responsibility for any loss, damage, or other consequence arising from or related to the use of, reliance on, or inability to use this report or the reviewed code. This includes, without limitation, direct, indirect, incidental, consequential, special, exemplary, or punitive damages, even if advised of the possibility of such damages.


This report reflects the results of a best-effort security review conducted within the scope and time constraints agreed upon with the client. Although an attempt was made to identify potential security issues, there is no assurance that all vulnerabilities have been discovered. A smart contract security review cannot be considered a guarantee or certification of security. Users and project teams remain solely responsible for the use, deployment, and management of any smart contracts.


This report does not constitute an endorsement or recommendation of the reviewed project. Third parties should not rely on this report and are strongly encouraged to perform their own independent assessments.

Page 2 of 8

---

## 3. Repository

[https://github.com/centrifuge/protocol-v3/](https://github.com/centrifuge/protocol-v3/)

<table>
<thead>
<tr><th>Version</th><th>Commit Hash</th><th>Date</th><th>Note</th></tr>
</thead>
<tbody>
<tr><td>First version (<sub>v1</sub>)</td><td>[2b657c3de80b2f1153ce64403209f2c8cb8527ac](https://github.com/centrifuge/protocol-v3/tree/2b657c3de80b2f1153ce64403209f2c8cb8527ac)</td><td>24th March 2025</td><td>First Version</td></tr>
<tr><td>Second review (<sub>v2</sub>)</td><td>[adea6c40869e529210005361d54add16507b108f](https://github.com/centrifuge/protocol-v3/tree/adea6c40869e529210005361d54add16507b108f)</td><td>1st April 2025</td><td>Second Version</td></tr>
</tbody>
</table>

## 4. Findings


The following findings were identified during the security review of the codebase. Each finding is categorized by severity level based on its potential impact and includes a detailed description and recommended remediation.

### Summary

<table>
<caption>Summary</caption>
<thead>
<tr><th>Severity</th><th>ID</th><th>Title</th><th>Status</th></tr>
</thead>
<tbody>
<tr><td>HIGH</td><td>H1</td><td>Missing auth modifier in Gateway.endBatch enables re-entrance for 3rd party-adapter contracts to resend the same batch multiple times</td><td>Fixed</td></tr>
<tr><td>MEDIUM</td><td>M1</td><td>PoolRouter.updateHoldingValue is not callable from the MessageProcessor due to access control restrictions</td><td>Fixed</td></tr>
<tr><td>LOW</td><td>L1</td><td>Calling Gateway.topUp twice in one transaction would result in the loss of fuel and ETH</td><td>Fixed</td></tr>
<tr><td>LOW</td><td>L2</td><td>Calling send with an empty message in isBatching mode will result in a separate empty bridge transaction instead of bundling it into a single one</td><td>Fixed</td></tr>
<tr><td>LOW</td><td>L3</td><td>Publicly callable Gateway.startBatch allows griefing attack in the same transaction</td><td>Fixed</td></tr>
<tr><td>INFORMATIONAL</td><td>I1</td><td>Incorrect assumptions in the comments about leftover token DUST in the MultiShareClass.claimDepositUntilEpoch</td><td>Fixed</td></tr>
</tbody>
</table>

Page 3 of 8

---

## HIGH Findings

**H1 Missing `auth` modifier in `<u>Gateway.endBatch</u>` enables re-entrance for 3rd party-adapter contracts to resend the same batch multiple times**

[Gateway.sol#L351](https://github.com/centrifuge/protocol-v3/blob/2b657c3de80b2f1153ce64403209f2c8cb8527ac/src/common/Gateway.sol#L351)

The Gateway allows bundling individual messages into a batch to send a transaction only once to multiple bridges. If batching is activated by calling `startBatch`, instead of sending a transaction to the bridge adapters, the `send` function stores them in a `batch`.

Only after a final `endBatch` call is the batch transaction sent. The `endBatch` function has no parameters and deletes the `batch` storage afterward, which is intended to be transient storage in later versions.

Therefore, the `endBatch` function is not using an `auth` modifier and can be called by anyone.

This enables a reentrance attack by third-party adapter contracts. A malicious adapter, called as part of the `_send` process in `endBatch`, could re-enter and call `endBatch` again.

```solidity
function endBatch() external {
    require(isBatching, NoBatched());
    for (uint256 i; i < chainIds.length; i++) {
        uint16 chainId = chainIds[i];
        _send(chainId, batch[chainId]);
        delete batch[chainId];
    }
    delete chainIds;
    pendingBatch = false;
    isBatching = false;
}
```

The `batch` is only deleted after the `_send` call, and the `isBatching` flag is set to `false` also after the call. The reentrance of the `endBatch` would allow `_send` to process any batch multiple times. This is a critical vulnerability since the transactions represent all the actions of the Centrifuge protocol. For example, a pool manager might allow redeeming x amount for a user, but sending the transaction multiple times to the vault would allow redeeming more funds, etc.

**Recommendation:** Add an `auth` modifier to `startBatch` and `endBatch`. The `endBatch` function should set `isBatching` and `<span style="color:#24292e">pendingBatch</span>` to false again before calling `_send`.

**Centrifuge:** Fixed in [centrifuge/protocol-v3#194](https://github.com/centrifuge/protocol-v3/pull/194)

## MEDIUM Findings

**M1. `<u>PoolRouter.updateHoldingValue</u>` is not callable from the `<u>MessageProcessor</u>` due to access control restrictions**

[PoolRouter.sol#L505](https://github.com/centrifuge/protocol-v3/blob/adea6c40869e529210005361d54add16507b108f/src/pools/PoolRouter.sol#L505)

**Description:** The `PoolRouter` contains functions that can only be called by the `poolAdmin`. The `poolAdmin` must first call `execute` to unlock the pool, which is only possible if the caller of `execute` is the `poolAdmin`.

```solidity
function execute(PoolId poolId, bytes[] calldata data) external payable {
    require(unlockedPoolId.isNull(), IPoolRouter.PoolAlreadyUnlocked());
```

Page 4 of 8

---

```solidity
    require(poolRegistry.isAdmin(poolId, msg.sender), IPoolRouter.NotAuthorizedAdmin());

    accounting.unlock(poolId);
    unlockedPoolId = poolId;

    multicall(data);

    accounting.lock();
    unlockedPoolId = PoolId.wrap(0);
}
```

Other functions have the `_protectedAndUnlocked` check, meaning they must be called via <u>`execute`</u>.

```solidity
/// @dev Ensure the method is protected (see `_protected()`) and the pool is unlocked,
/// which means the method must be called through `execute()`
function _protectedAndUnlocked() internal protected {
    require(!unlockedPoolId.isNull(), IPoolRouter.PoolLocked());
}

function updateHolding(ShareClassId scId, AssetId assetId) public payable {
    _protectedAndUnlocked();
    // ...
}
```

The `updateHolding` function uses the `_protectedAndUnlocked` check. However, there is another function, `updateHoldingValue`, which uses the `auth` pattern and calls `updateHolding`.

```solidity
function updateHoldingValue(PoolId poolId, ShareClassId scId, AssetId assetId, D18 pricePerUnit)
external auth {
    // ...
    updateHolding(scId, assetId);
    // ...
}
```


The `updateHoldingValue` function is triggered by a vault bridge transaction, and the `MessageProcessor` contract, which is a `ward` on the `PoolRouter`, should call `updateHoldingValue`. However, the internal `updateHolding` call requires the `poolAdmin` execute flow, causing this function to always revert.

**Recommendation:** Use an internal `_updateHolding` function to reuse the logic of `updateHolding`. The `updateHoldingValue` function should call `_updateHolding` to bypass the access control check.

**Centrifuge:** Fixed in [centrifuge/protocol-v3#244.](https://github.com/centrifuge/protocol-v3/pull/244/)

**xmxanuel:** Fixed.

## LOW Findings

**L1. Calling `Gateway.topUp` twice in one transaction would result in the loss of `fuel` and `ETH`**

[Gateway.sol#L336](https://github.com/centrifuge/protocol-v3/blob/2b657c3de80b2f1153ce64403209f2c8cb8527ac/src/common/Gateway.sol#L336)

**Description:** The `Gateway` needs to pay for the transactions to the bridges. Therefore, contracts using the gateway can call `topUp` to deposit `ETH` for an upcoming `send` call.

Page 5 of 8

---

The transferred ETH is reflected in the transient <u>`fuel`</u> variable.

However, if the <u>`topUp`</u> is called twice, the previous <u>`fuel`</u> value will be overwritten.

This means the <u>`send`</u> call would have less <u>`fuel`</u> available, and the additional deposited ETH is lost.

```solidity
if (!isBatching || pendingBatch) {
    require(msg.value != 0, "Gateway/cannot-topup-with-nothing");
    fuel = msg.value;
}
```

In the current implementation, all contracts using the `Gateway` call `topUp` and `send` only once, so it is not an issue.

**Recommendation:** Allow the `topUp` function to be called multiple times before calling `send` and add the `msg.value` to the existing `fuel`.

```diff
 if (!isBatching || pendingBatch) {
     require(msg.value != 0, "Gateway/cannot-topup-with-nothing");
-    fuel = msg.value;
+    fuel += msg.value;
 }
```

**Centrifuge**: Fixed in [centrifuge/protocol-v3#194.](https://github.com/centrifuge/protocol-v3/pull/194)

**xmxanuel**: Fixed.

**L2. Calling <u>`send`</u> with an empty message in `<u>isBatching</u>` mode will result in a separate empty bridge transaction instead of bundling it into a single one**

[Gateway.sol#L266](https://github.com/centrifuge/protocol-v3/blob/2b657c3de80b2f1153ce64403209f2c8cb8527ac/src/common/Gateway.sol#L266)

**Description:** When the `Gateway` is in batching mode, calling the `send` function with an empty message will still add the `chainId` to the `chainIds` array. If the same `chainId` is called again with an actual message, the `chainId` will be pushed a second time to the `chainIds`.

This leads to a situation where the same <u>`chainId`</u> appears twice in the array.

```solidity
if (isBatching) {
    pendingBatch = true;

    bytes storage previousMessage = batch[chainId];
    if (previousMessage.length == 0) {
        chainIds.push(chainId);
        batch[chainId] = message;
    } else {
        batch[chainId] = bytes.concat(previousMessage, message);
    }
}
```

**Recommendation:** Ensure that the <u>`send`</u> function is only called with a non-empty message when in batching mode.

During the execution of `endBatch`, after processing the first occurrence of a `chainId` with an actual message via `_send`, the `batch[chainId]` is deleted. Consequently, when the second occurrence of the same `chainId` is processed, `_send` is called with an empty message, resulting in an unnecessary empty bridge transaction.

Page 6 of 8

---

**Centrifuge**: Fixed in [centrifuge/protocol-v3#194](https://github.com/centrifuge/protocol-v3/pull/194).

**xmxanuel**: Fixed.

## L3. Publicly callable `<u>Gateway.startBatch</u>` allows griefing attack in the same transaction


[VaultRouter.sol#L51](https://github.com/centrifuge/protocol-v3/blob/2b657c3de80b2f1153ce64403209f2c8cb8527ac/src/vaults/VaultRouter.sol#L51)


**Description:** The `batching` of transactions can be exploited by a griefing attack within the same overall Ethereum transaction. The `<u>Gateway.startBatch</u>` function, which initiates the batching process, sets the transient storage flag `isBatching` to true.


The `multicall` function in both `VaultRouter` and `PoolRouter` only tops up the gateway for paying transactions if `isBatching()` has not been started. This logic is intended to allow `multicalls` within `multicalls` but can be exploited through a griefing attack.


```solidity
function multicall(bytes[] calldata data) public payable override(Multicall, IMulticall) {
    bool wasBatching = gateway.isBatching();
    if (!wasBatching) {
        gateway.startBatch();
    }

    super.multicall(data);

    if (!wasBatching) {
        gateway.topUp{value: msg.value}();
        gateway.endBatch();
    }
}
```


The transient storage persists throughout the entire transaction. If untrusted third-party code is executed within the same transaction, such as by sending ETH to a contract address, an attacker could call <u>`startBatch`</u>. This would cause the actual multicall transaction to revert because the gateway did not receive an ETH top-up.


**Recommendation:** Implement access control to restrict who can call `startBatch`. Ensure that the `multicall` function handles the `isBatching` state securely to prevent unauthorized manipulation.


**Centrifuge:** Fixed in [centrifuge/protocol-v3#194](https://github.com/centrifuge/protocol-v3/pull/194).


**xmxanuel:** Fixed.

# Informational

## I1. Incorrect assumptions in the comments about leftover token <u>`DUST`</u> in the `<u>MultiShareClass.claimDepositUntilEpoch</u>`


[https://github.com/centrifuge/protocol-v3/blob/2b657c3de80b2f1153ce64403209f2c8cb8527ac/src/pools/MultiShareClass.sol#L422](https://github.com/centrifuge/protocol-v3/blob/2b657c3de80b2f1153ce64403209f2c8cb8527ac/src/pools/MultiShareClass.sol#L422)


**Description:** The comments in the claimDepositUntilEpoch function suggest that leftover token DUST is limited to a single atom. However, this assumption is incorrect. The discrepancy between the sum of claimable user amounts and the total issued share class tokens can be more than a single atom, as demonstrated in the following example.


**Example Testcase**

Page 7 of 8

---

```solidity
function testSumAllUsersLessThanIssuedShareAmount() public {
    uint navPerShare = 1.5 * 1e18;
    // Assume 3 users with deposits of 33, 33, and 34, totaling 100
    // All deposits are approved, and currency equals asset in value
    uint depositPool = 100 * 1e18;
    uint issuedShareAmount = depositPool * 1e18 / navPerShare;
    console.log("issuedShares", issuedShareAmount);

    // approveDeposits will be 100 * 1e18 and currency equals asset
    uint depositApproved = depositPool;

    // claimDepositUntilEpoch calculations for the 3 users
    uint claimableShareAmount_user1 = 33 * 1e18 * issuedShareAmount / depositApproved;
    uint claimableShareAmount_user2 = 34 * 1e18 * issuedShareAmount / depositApproved;
    uint claimableShareAmount_user3 = 33 * 1e18 * issuedShareAmount / depositApproved;

    uint sumAllUsers = claimableShareAmount_user1 + claimableShareAmount_user2 +
claimableShareAmount_user3;

    assertEq(sumAllUsers, issuedShareAmount, "issuedShareAmount not equal sumAllUsers");
}
```

## Output

```text
[FAIL: issuedShareAmount not equal sumAllUsers: 66666666666666666664 != 66666666666666666666]
testSumAllUsersLessThanIssuedShareAmount() (gas: 7316)
```

In this example, the sum of claimable shares for all users is less than the issued share amount by 2 atoms, not just 1. This indicates that the leftover DUST can be more than a single atom, contrary to the comment's implication.


**Recommendation:** Update the comments to reflect that the leftover `DUST` can be more than a single atom, especially in scenarios involving multiple investors. This will provide a more accurate understanding of potential discrepancies in share distribution.

**Centrifuge:** Fixed in [3e82ccb](https://github.com/centrifuge/protocol-v3/pull/201/commits/3e82ccb70c61a3f4785b1f09180fae8858992781).

**xmxanuel:** Fixed.

Page 8 of 8