![logo: BURRA SEC wordmark](page_1_image_1_v2.jpg)

# **Centrifuge Security Review**

Reviewed by: Goran Vladika

21st May - 23rd May, 2025

---

Centrifuge Security Review Report
May 27, 2025

# Centrifuge Security Review Report


Burra Security
May 27, 2025


## Introduction


A time-boxed security review of the **Centrifuge** protocol was done by **Burra Security** team, focusing on the security aspects of the smart contracts.


## Disclaimer


A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource, and expertise-bound effort where we try to find as many vulnerabilities as possible. We can not guarantee 100% security after the review or even if the review will find any vulnerabilities. Subsequent security reviews, bug bounty programs, and on-chain monitoring are recommended.


## About Burra Security


Burra Sec offers security auditing and advisory services with a special focus on cross-chain and interoperability protocols and their integrations.


## About Centrifuge


Centrifuge V3 is an open, decentralized protocol for onchain asset management. Built on immutable smart contracts, it enables permissionless deployment of customizable tokenization products.





2

Burra Security

---

<u>Centrifuge Security Review Report</u> <u>May 27, 2025</u>

Build a wide range of use cases—from permissioned funds to onchain loans—while enabling fast, secure deployment. ERC-4626 and ERC-7540 vaults allow seamless integration into DeFi. Using protocol-level chain abstraction, tokenization issuers access liquidity across any network, all managed from one Hub chain of their choice.

## **Severity classification**

<table>
<thead>
<tr><th>Severity</th><th>Impact: High</th><th>Impact: Medium</th><th>Impact: Low</th></tr>
</thead>
<tbody>
<tr><td><b><b>Likelihood: High</b></b></td><td>Critical</td><td>High</td><td>Medium</td></tr>
<tr><td><b><b>Likelihood: Medium</b></b></td><td>High</td><td>Medium</td><td>Low</td></tr>
<tr><td><b><b>Likelihood: Low</b></b></td><td>Medium</td><td>Low</td><td>Low</td></tr>
</tbody>
</table>

**Impact** - The technical, economic, and reputation damage from a successful attack

**Likelihood** - The chance that a particular vulnerability gets discovered and exploited

**Severity** - The overall criticality of the risk

**Informational** - Findings in this category are recommended changes for improving the structure, usability, and overall effectiveness of the system.

## **Security Assessment Summary**

***review commit hash* - [7762b38519e2f77cd0f03ff7e43ff765bfb630ad](https://github.com/centrifuge/protocol-v3/tree/7762b38519e2f77cd0f03ff7e43ff765bfb630ad)**

### **Scope**

The following smart contracts were in the scope of the audit:

- [src/hub/Hub.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/hub/Hub.sol)
- [src/hub/HubHelpers.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/hub/HubHelpers.sol)
- [src/common/adapters/MultiAdapter.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/common/adapters/MultiAdapter.sol)
- [src/common/adapters/AxelarAdapter.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/common/adapters/AxelarAdapter.sol)
- [src/common/adapters/WormholeAdapter.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/common/adapters/WormholeAdapter.sol)
- [src/common/Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/common/Gateway.sol)
- [src/common/GasService.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/common/GasService.sol)



3

Burra Security

---

<u>Centrifuge Security Review Report</u>
<u>May 27, 2025</u>

- [src/misc/libraries/TransientArrayLib.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/misc/libraries/TransientArrayLib.sol)
- [src/misc/libraries/TransientBytesLib.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/misc/libraries/TransientBytesLib.sol)

## Findings Summary

<table>
<thead>
<tr><th>ID</th><th>Title</th><th>Severity</th><th>Status</th></tr>
</thead>
<tbody>
<tr><td>L-01</td><td>Deployer’s auth access on MultiAdapter should be revoked</td><td>Low</td><td>Resolved</td></tr>
<tr><td>L-02</td><td>Missing setter for hubHelpers in Hub</td><td>Low</td><td>Resolved</td></tr>
</tbody>
</table>

## Detailed Findings

### [L-01] Deployer’s auth access on MultiAdapter should be revoked

#### Target

- [CommonDeployer.s.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/script/CommonDeployer.s.sol)

#### Severity:

- Impact: Medium
- Likelihood: Low

#### Description:

As part of the deployment process deployer account is initially set as an admin on the protocol contracts. Then this access is revoked on most of the contracts, but not on the multiAdapter:

```solidity
function removeCommonDeployerAccess(address deployer) public {
    if (root.wards(deployer) == 0) {
        return; // Already removed. Make this method idempotent.
    }

    guardian.file("safe", address(adminSafe));
```



4

Burra Security

---

<u>Centrifuge Security Review Report</u>　　　　　　　　　　　　　　　　　　　　　　　　<u>May 27, 2025</u>

```text
   7
   8           <span style="color:#435489">root.deny(deployer);</span>
   9           <span style="color:#435489">gateway.deny(deployer);</span>
  10           <span style="color:#435489">tokenRecoverer.deny(deployer);</span>
  11           <span style="color:#435489">messageProcessor.deny(deployer);</span>
  12           <span style="color:#435489">messageDispatcher.deny(deployer);</span>
```


That means deployer account keeps their admin access. If attacker would gain access over this account, there could be a lot of damage done to the protocol.


**Recommendation:**


Revoke deployer's auth access from the multiAdapter as well:


```text
  1          <span style="color:#435489">multiAdapter.deny(deployer);</span>
```


**Client:**


Fixed in [PR-399](https://github.com/centrifuge/protocol-v3/pull/399)


**BurraSec:**


Fix verified


## **[L-02] Missing setter for hubHelpers in Hub**


### **Target**


- [Hub.sol](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/hub/Hub.sol)


### **Severity:**


- Impact: Medium


- Likelihood: Low

Burra Security

---

<u>Centrifuge Security Review Report</u>

<u>May 27, 2025</u>

**Description:**

Hub contract has a storage variable which stores the address of the [hubHelpers](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/hub/Hub.sol#L39) contract. Even though hubHelpers variable is not immutable, its value can be set only in constructor. If hubHelpers address changed, ie. due to the updated implementation of some of the hub actions, there would be no way to point the Hub contract to the new hubHelpers address. This increases the complexity of protocol maintenance.

**Recommendation:**

Add the option to update the hubHelpers in the [file](https://github.com/centrifuge/protocol-v3/blob/7762b38519e2f77cd0f03ff7e43ff765bfb630ad/src/hub/Hub.sol#L72) function.

**Client:**

Fixed in [PR-399](https://github.com/centrifuge/protocol-v3/pull/399)

**BurraSec:**

Fix verified



6

Burra Security