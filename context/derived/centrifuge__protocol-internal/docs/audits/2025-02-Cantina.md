![logo: CANTINA wordmark](kbsl)

# **Centrifuge Vaults**

**Security Review**

Cantina Managed review by:

**Gerard Persoon**, Lead Security Researcher
**0xDjango**, Associate Security Researcher

February 22, 2025

---

<table>
<tr><td><b>1</b></td><td><b>Introduction</b></td><td><b>2</b></td></tr>
<tr><td>1.1</td><td>About Cantina</td><td>2</td></tr>
<tr><td>1.2</td><td>Disclaimer</td><td>2</td></tr>
<tr><td>1.3</td><td>Risk assessment</td><td>2</td></tr>
<tr><td>1.3.1</td><td>Severity Classification</td><td>2</td></tr>
<tr><td><b>2</b></td><td><b>Security Review Summary</b></td><td><b>3</b></td></tr>
<tr><td><b>3</b></td><td><b>Findings</b></td><td><b>4</b></td></tr>
<tr><td>3.1</td><td>Low Risk</td><td>4</td></tr>
<tr><td>3.1.1</td><td>Checks in _processRedeem() can be circumvented and is missing in claimCancelDe-<br />positRequest()</td><td>4</td></tr>
<tr><td>3.2</td><td>Gas Optimization</td><td>4</td></tr>
<tr><td>3.2.1</td><td>Functions in ERC7540Vault can be made external</td><td>4</td></tr>
<tr><td>3.3</td><td>Informational</td><td>5</td></tr>
<tr><td>3.3.1</td><td>Unused bits are erased in updateMember()</td><td>5</td></tr>
<tr><td>3.3.2</td><td>Different order of parameters in events Cancel...Claim</td><td>5</td></tr>
<tr><td>3.3.3</td><td>Similar checks done in different places</td><td>6</td></tr>
<tr><td>3.3.4</td><td>Comment in _canTransfer() can be improved to be easier to understand</td><td>6</td></tr>
<tr><td>3.3.5</td><td>Comment can be updated to provide more detail</td><td>6</td></tr>
<tr><td>3.3.6</td><td>maxRedeem() and maxWithdraw() don't have _canTransfer() check</td><td>6</td></tr>
</table>

1

---

# 1 Introduction

## 1.1 About Cantina

Cantina is a security services marketplace that connects top security researchers and solutions with clients. Learn more at [cantina.xyz](https://cantina.xyz)

## 1.2 Disclaimer

Cantina Managed provides a detailed evaluation of the security posture of the code at a particular moment based on the information available at the time of the review. While Cantina Managed endeavors to identify and disclose all potential security issues, it cannot guarantee that every vulnerability will be detected or that the code will be entirely secure against all possible attacks. The assessment is conducted based on the specific commit and version of the code provided. Any subsequent modifications to the code may introduce new vulnerabilities that were absent during the initial review. Therefore, any changes made to the code require a new security review to ensure that the code remains secure. Please be advised that the Cantina Managed security review is not a replacement for continuous security measures such as penetration testing, vulnerability scanning, and regular code reviews.

## 1.3 Risk assessment

<table>
<thead>
<tr><th>Severity</th><th><b>Description</b></th></tr>
</thead>
<tbody>
<tr><td><b>Critical</b></td><td><i>Must</i> fix as soon as possible (if already deployed).</td></tr>
<tr><td><b>High</b></td><td>Leads to a loss of a significant portion (>10%) of assets in the protocol, or sig-<br />nificant harm to a majority of users.</td></tr>
<tr><td><b>Medium</b></td><td>Global losses &#x3C;10% or losses to only a subset of users, but still unacceptable.</td></tr>
<tr><td><b>Low</b></td><td>Losses will be annoying but bearable. Applies to things like griefing attacks that<br />can be easily repaired or even gas inefficiencies.</td></tr>
<tr><td><b><b>Gas Optimization</b></b></td><td>Suggestions around gas saving practices.</td></tr>
<tr><td><b>Informational</b></td><td>Suggestions around best practices or readability.</td></tr>
</tbody>
</table>

### 1.3.1 Severity Classification

The severity of security issues found during the security review is categorized based on the above table. Critical findings have a high likelihood of being exploited and must be addressed immediately. High findings are almost certain to occur, easy to perform, or not easy but highly incentivized thus must be fixed as soon as possible.

Medium findings are conditionally possible or incentivized but are still relatively likely to occur and should be addressed. Low findings a rare combination of circumstances to exploit, or offer little to no incentive to exploit but are recommended to be addressed.

Lastly, some findings might represent objective improvements that should be addressed but do not impact the project's overall security (Gas and Informational findings).

2

---

## 2 Security Review Summary


Centrifuge empowers asset managers to tokenize, manage, and distribute their funds onchain, while providing investors access to a diversified group of tokenized assets.


From Feb 11th to Feb 16th the Cantina team conducted a review of [vaults-internal](https://github.com/centrifuge/vaults-internal) on commit hash [70c00ee6.](https://github.com/centrifuge/vaults-internal/tree/70c00ee6b74edc10765f7abbb21451e6bb243e96) The team identified a total of **8** issues:


**Issues Found**

<table>
<thead>
<tr><th>Severity</th><th>Count</th><th>Fixed</th><th>Acknowledged</th></tr>
</thead>
<tbody>
<tr><td>Critical Risk</td><td>0</td><td>0</td><td>0</td></tr>
<tr><td>High Risk</td><td>0</td><td>0</td><td>0</td></tr>
<tr><td>Medium Risk</td><td>0</td><td>0</td><td>0</td></tr>
<tr><td>Low Risk</td><td>1</td><td>1</td><td>0</td></tr>
<tr><td>Gas Optimizations</td><td>1</td><td>1</td><td>0</td></tr>
<tr><td>Informational</td><td>6</td><td>5</td><td>1</td></tr>
<tr><th>Total</th><th>8</th><th>7</th><th>1</th></tr>
</tbody>
</table>


3

---

# 3 Findings

## 3.1 Low Risk

### 3.1.1 Checks in `_processRedeem()` **can be circumvented and is missing in** `claimCancelDepositRequest()`

**Severity:** Low Risk

**Context:** <span style="color:#55747d">[InvestmentManager.sol#L97-L109,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L97-L109)</span> <span style="color:#55747d">[InvestmentManager.sol#L524-L533,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L524-L533)</span> [InvestmentManager.sol#L543-L554,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L543-L554) [RestrictedRedemptions.sol#L67-L71,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/token/RestrictedRedemptions.sol#L67-L71) [RestrictionManager.sol#L64-L67](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/token/RestrictionManager.sol#L64-L67)

**Description:** In `_processRedeem()`, `receiver` can be arbitrarily selected via `redeem()` and `withdraw()`. `RestrictionManager` and `RestrictedRedemptions` both have the following restrictions on `from`:

```solidity
if (<span style="color:#214a87">uint128</span>(hookData.from).getBit(FREEZE_BIT) == <span style="color:#214a87">true</span> <span style="color:#cf5c00">&& !</span>root.endorsed(from)) {
    <span style="color:#8f5903">// Source is frozen and not endorsed</span>
    <span style="color:#214a87">return false</span>;
}
```

The caller of `redeem()` and `withdraw()` can choose a `receiver` that doesn't have the `FREEZE_BIT` set, so the `_canTransfer()` check can be circumvented.

*Note: this assumes `address(0)` doesn't have the `FREEZE_BIT` set, but if that would be the case `_processRedeem()` would never work.*

Additionally `claimCancelDepositRequest()` also transfers assets but has no checks and `receiver` can also be arbitrarily selected.

**Recommendation:** Consider adding a `_canTransfer()` check to both `_processRedeem()` where `controller` is used as the `from`. Also add similar checks in `claimCancelDepositRequest()`.

*Note: this requires adding `controller` as a parameter to `_processRedeem()`.*

*Note: this is similar to the check on `controller` in `InvestmentManager::requestRedeem()`.*

A possible solution as suggested by the project is adding the following:

```solidity
if (controller != receiver) {
    require(
        _canTransfer(vault, controller, receiver, convertToShares(vault, assetsDown)),
        // ...
    )
}
```

**Centrifuge:** Fixed in [PR 96.](https://github.com/centrifuge/vaults-internal/pull/96)

**Cantina Managed:** Fix verified.

## 3.2 Gas Optimization

### 3.2.1 Functions in ERC7540Vault can be made external

**Severity:** Gas Optimization

**Context:** [ERC7540Vault.sol#L26,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/ERC7540Vault.sol#L26) [ERC7540Vault.sol#L341](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/ERC7540Vault.sol#L341)

**Description:** Several functions in `ERC7540Vault` as public while they are not called from the contract itself:

4

---

```solidity
function requestDeposit(uint256 assets, address controller, address owner) public returns (uint256) {
function pendingDepositRequest(uint256, address controller) public view returns (uint256 pendingAssets) {
function requestRedeem(uint256 shares, address controller, address owner) public returns (uint256) {
function pendingRedeemRequest(uint256, address controller) public view returns (uint256 pendingShares) {
function pendingCancelDepositRequest(uint256, address controller) public view returns (bool isPending) {
function claimableCancelDepositRequest(uint256, address controller) public view returns (uint256 claimableAssets) {
function pendingCancelRedeemRequest(uint256, address controller) public view returns (bool isPending) {
function claimableCancelRedeemRequest(uint256, address controller) public view returns (uint256 claimableShares) {
function setOperator(address operator, bool approved) public virtual returns (bool success) {
function setEndorsedOperator(address owner, bool approved) public virtual {
function convertToShares(uint256 assets) public view returns (uint256 shares) {
function maxDeposit(address controller) public view returns (uint256 maxAssets) {
function maxMint(address controller) public view returns (uint256 maxShares) {
function mint(uint256 shares, address receiver) public returns (uint256 assets) {
function maxWithdraw(address controller) public view returns (uint256 maxAssets) {
function withdraw(uint256 assets, address receiver, address controller) public returns (uint256 shares) {
function onRedeemRequest(address controller, address owner, uint256 shares) public auth {
function onDepositClaimable(address controller, uint256 assets, uint256 shares) public auth {
function onRedeemClaimable(address controller, uint256 assets, uint256 shares) public auth {
function onCancelDepositClaimable(address controller, uint256 assets) public auth {
function onCancelRedeemClaimable(address controller, uint256 shares) public auth {
```

*Note: the following functions are called from the contract, so should stay public*:


```solidity
function DOMAIN_SEPARATOR() public view returns (bytes32) {
function convertToAssets(uint256 shares) public view returns (uint256 assets) {
function deposit(uint256 assets, address receiver, address controller) public returns (uint256 shares) {
function mint(uint256 shares, address receiver, address controller) public returns (uint256 assets) {
function maxRedeem(address controller) public view returns (uint256 maxShares) {
```


**Recommendation:** Consider making these functions `external` to save some gas.


**Centrifuge:** Fixed in [PR 96.](https://github.com/centrifuge/vaults-internal/pull/96)


**Cantina Managed:** Fix verified.


## 3.3 Informational


### 3.3.1 Unused bits are erased in `updateMember()`


**Severity:** Informational


**Context:** [RestrictedRedemptions.sol#L129-L138,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/token/RestrictedRedemptions.sol#L129-L138) [RestrictionManager.sol#L125-L133](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/token/RestrictionManager.sol#L125-L133)


**Description:** The functions `updateMember()` in `RestrictedRedemptions` and `RestrictionManager` update the timestamp and the `FREEZE_BIT`. However they don't retreive and maintain the remaining 63 bits of the `hookData`, so the unused bits are erased. If more bits would be used in the future it might be useful to keep them.


**Recommendation:** Consider keeping the unused bits from `hookData`.


**Centrifuge:** This shouldn't be an issue, since the contract is non-upgradeable, any future implementation using more bits would use other logic.


**Cantina Managed:** Acknowledged.


### 3.3.2 Different order of parameters in events `Cancel...Claim`


**Severity:** Informational


**Context:** [ERC7540Vault.sol#L179,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/ERC7540Vault.sol#L179) [ERC7540Vault.sol#L206](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/ERC7540Vault.sol#L206)


**Description:** The following events start with `receiver` and then `controller`. However most events start with `controller`, followed by `receiver`.


```solidity
emit CancelDepositClaim(receiver, controller, REQUEST_ID, msg.sender, assets);
emit CancelRedeemClaim(receiver, controller, REQUEST_ID, msg.sender, shares);
```


5

---

**Recommendation:** Consider using the same order in all events.

**Centrifuge:** Fixed in [PR 96](https://github.com/centrifuge/vaults-internal/pull/96).

**Cantina Managed:** Fix verified.

### 3.3.3 Similar checks done in different places

**Severity:** Informational

**Context:** [ERC7540Vault.sol#L119-L132,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/ERC7540Vault.sol#L119-L132) [InvestmentManager.sol#L97-L109](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L97-L109)

**Description:** Function `ERC7540Vault::requestRedeem()` calls `checkTransferRestriction()` and `InvestmentManager::requestRedeem()`. Function `InvestmentManager::requestRedeem()` calls `_canTransfer()`, which is similar to `checkTransferRestriction()`. So two similar checks are done in different places.

**Recommendation:** Consider putting the checks in the same location, which is easier to read and maintain.

**Centrifuge:** Fixed in [PR 96](https://github.com/centrifuge/vaults-internal/pull/96).

**Cantina Managed:** Fix verified.

### 3.3.4 Comment in `_canTransfer()` can be improved to be easier to understand

**Severity:** Informational

**Context:** [InvestmentManager.sol#L641-L646](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L641-L646)

**Description:** The following comment in `InvestmentManager::_canTransfer()` can be improved to make it more readable:

```diff
- Sender (from) and receiver (to) have both to pass
+ Sender (from) and receiver (to) have to both pass
```

**Centrifuge:** Fixed in [PR 96](https://github.com/centrifuge/vaults-internal/pull/96).

**Cantina Managed:** Fix verified.

### 3.3.5 Comment can be updated to provide more detail

**Severity:** Informational

**Context:** [ERC7540Vault.sol#L340-L341,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/ERC7540Vault.sol#L340-L341) [ERC7540Vault.sol#L353-L356](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/ERC7540Vault.sol#L353-L356)

**Description:** Comments in the `withdraw()` and `redeem()` functions state: `DOES NOT support controller != msg.sender`. However, this is not completely accurate. `msg.sender` can be different than the controller if `msg.sender` happens to be an operator of `controller`.

**Recommendation:** Consider updating the comment to make this clear.

**Centrifuge:** Fixed in [PR 96](https://github.com/centrifuge/vaults-internal/pull/96).

**Cantina Managed:** Fix verified.

### 3.3.6 `maxRedeem()` and `maxWithdraw()` don't have `_canTransfer()` check

**Severity:** Informational

**Context:** [InvestmentManager.sol#L267,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L267) [InvestmentManager.sol#L281-L282,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L281-L282) [InvestmentManager.sol#L389-<span style="color:#55747d">L390](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L389-L390), [InvestmentManager.sol#L400-L401,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L400-L401) [InvestmentManager.sol#L406,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L406) [InvestmentManager.sol#L411,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L411)</span> <span style="color:#55747d">[InvestmentManager.sol#L454,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L454) [InvestmentManager.sol#L469,](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L469) [InvestmentManager.sol#L524-L535](https://cantina.xyz/code/3a77b988-b9e3-4d3e-86ea-f1df5b87007c/vaults-internal/src/InvestmentManager.sol#L524-L535)</span>

**Description:** The functions `Redeem()` and `Withdraw()` call `_processRedeem()`, which now has a `_canTransfer()` check. The related functions `maxRedeem()` and `maxWithdraw()` don't have such a check. However the functions `maxMint()` and `maxDeposit()`, which are similar to `maxRedeem()` and `maxWithdraw()`, do have a `_canTransfer()` check.

**Recommendation:** Consider adding a `_canTransfer()` check to `maxRedeem()` and `maxWithdraw()`.

**Centrifuge:** Fixed in [PR 96.](https://github.com/centrifuge/vaults-internal/pull/96)

6

---

**Cantina Managed:** Fix verified.

7