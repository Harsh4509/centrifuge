![logo: BURRA SEC wordmark](page_1_image_1_v2.jpg)

# **Centrifuge Security Review**

Reviewed by: Goran Vladika, Pranav Garg

April 9th - April 15th, 2025

---

Centrifuge Security Review Report April 25, 2025

# Centrifuge Security Review Report

Burra Security

April 25, 2025

## Introduction

A time-boxed security review of the **Centrifuge** protocol was done by **Burra Security** team, focusing on the security aspects of the smart contracts.

## Disclaimer

A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource, and expertise-bound effort where we try to find as many vulnerabilities as possible. We can not guarantee 100% security after the review or even if the review will find any vulnerabilities. Subsequent security reviews, bug bounty programs, and on-chain monitoring are recommended.

## About Burra Security

Burra Security offers security auditing and advisory services with a special focus on cross-chain and interoperability protocols and their integrations.

## About Centrifuge

Centrifuge V3 is an open, decentralized protocol for onchain asset management. Built on immutable smart contracts, it enables permissionless deployment of customizable tokenization products.

Using protocol-level chain abstraction, tokenization issuers access liquidity across any network, all managed from one Hub chain of their choice.



2

Burra Security

---

<u>Centrifuge Security Review Report</u> <u>April 25, 2025</u>

# Severity classification

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

## Security Assessment Summary

***review commit hash*** - **[af76d5a74c9c575572c66e4a1c10ba1b182032f5](https://github.com/centrifuge/protocol-v3/tree/af76d5a74c9c575572c66e4a1c10ba1b182032f5)**

### **Scope**

The following smart contracts were in the scope of the audit:

- [Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/Gateway.sol)
- [WormholeAdapter.sol](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/WormholeAdapter.sol)
- [AxelarAdapter.sol](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/AxelarAdapter.sol)
- [GasService.sol](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/GasService.sol)

## Findings Summary

Burra Security
3

---

<u>Centrifuge Security Review Report</u>

<u>April 25, 2025</u>

<table>
<thead>
<tr><th>ID</th><th>Title</th><th>Severity</th><th>Status</th></tr>
</thead>
<tbody>
<tr><td>H-01</td><td>Gateway is used as the refund receiver, but lacks ability to receive<br />ETH</td><td>High</td><td>Resolved</td></tr>
<tr><td>M-01</td><td>User is not refunded the difference between msg.value and the<br />actual cost</td><td>Medium</td><td>Resolved</td></tr>
<tr><td>L-01</td><td>Executing failed messages should be disabled when system is<br />paused</td><td>Low</td><td>Resolved</td></tr>
<tr><td>I-01</td><td>Not resetting the transient storage vars can cause issues</td><td>Info</td><td>Resolved</td></tr>
<tr><td>I-02</td><td>Ensure the correctness of refundWormholeId</td><td>Info</td><td>Resolved</td></tr>
<tr><td>I-03</td><td>Mismatch between SendProof and ProcessProof events</td><td>Info</td><td>Resolved</td></tr>
</tbody>
</table>

## Detailed Findings

### **[H-01] Gateway is used as the refund receiver, but lacks ability to receive ETH**

#### **Target**

- <span style="color:#435489">[Gateway</span>.sol](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/Gateway.sol)

#### **Severity**

- Impact: Medium
- Likelihood: High

#### **Description**

When gateway calls adapter to send the cross-chain message, it [sets itself](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/Gateway.sol#L297) as a refund receiver. Both Wormhole and Axelar have similar refund mechanisms - user pays on the source chain for a certain amount of gas to be spent on the destination chain. If actual gas consumption on the destination chain turns out to be lower, the payment for unspent gas will be refunded by relayer to the refund receiver. That’s where the issue is, <span style="color:#435489">`Gateway`</span> contract is the refund receiver, but since it does not implement <span style="color:#435489">`receive()`</span> function it can’t receive the refunded ETH.



4

Burra Security

---

<u>Centrifuge Security Review Report</u> <u>April 25, 2025</u>

And the likelihood of refund being triggered for every message is quite high due to the current design of <span style="color:#435489">`GasService`</span>. It uses immutable gasLimit for every message type, no matter how much gas is required to process the specific message. The <span style="color:#435489">`gasLimit`</span> value has to be set such that it covers the execution of the most gas-intensive message. So for the most messages refund mechanism will be triggered, and the funds to be refunded will be effectively lost for the protocol.

## **Recommendation**


Add <span style="color:#435489">`receive`</span> function to the Gateway and track senders to be able to identify refunds.


```text
1      <span style="color:#435489">receive() external payable</span> {
2          <span style="color:#435489">emit Received(msg.sender, msg.value);</span>
3      }
```

## **BurraSec**


Fix in [PR#253](https://github.com/centrifuge/protocol-v3/pull/253) looks good, gateway can now receive direct transfers

## **[M-01] User is not refunded the difference between msg.value and the actual cost**

### **Target**

- [Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/Gateway.sol)

### **Severity**

- Impact: Medium
- Likelihood: Medium

### **Description**


When doing the cross-chain calls, user provides ETH along with the call to pay for the message or the whole batch. <span style="color:#435489">`Estimate(...)`</span> functions can be used off-chain to figure out the amount of fees to provide. However, gas price can fluctuate and change between estimation and the time of the actual TX execution. In case the fees turn out to be overpaid, the difference between msg.value and the actual

Burra Security

---

<u>Centrifuge Security Review Report</u>

<u>April 25, 2025</u>

cost is not refunded back to the user. Overpaid fees stay in the <span style="color:#435489">`Gateway`</span> contract where they can only be recovered by the admin actions.

## Recommendation

Send back the remaining <span style="color:#435489">`fuel`</span> to the user after the message or the batch are sent out.

## BurraSec

Fix in [PR#253](https://github.com/centrifuge/protocol-v3/pull/253) looks good, remaining fuel is sent to TX payer

## [L-01] Executing failed messages should be disabled when system is paused

### **Target**

- [Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/Gateway.sol)

### **Severity**

- Impact: Medium
- Likelihood: Low

### **Description**

In case of an emergency, system can be paused which will in turn disable sending and receiving of cross-chain messages. However, executing the previously failed messages via [retry](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/Gateway.sol#L204) function won’t be disabled. That fact can be possibly exploited by an attacker. Attacker could pre-plant a failing message, then wait for an emergency situation where message could be re-tried and cause harm to the protocol.

### **Recommendation**

Make <span style="color:#435489">`retry`</span> function pausable.



6

Burra Security

---

<u>Centrifuge Security Review Report</u>

<u>April 25, 2025</u>

### **Client**

Fixed in https://github.com/centrifuge/protocol-v3/pull/254/files

### **BurraSec**

Fix looks good

## **[I-01] Not resetting the transient storage vars can cause issues**

### **Target**

- [Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/Gateway.sol)

### **Severity**

- Impact: Low
- Likelihood: Low

### **Description**

Gateway uses transient storage to handle the batch message processing. At the end of the batch, some transient vars are reset to default values, but <span style="color:#435489">paymentMethod</span> is not. That’s not an issue in a typical case where ie. <span style="color:#435489">VaultRouter</span>’s <span style="color:#435489">multicall</span> is the top level call of the transaction. But that’s not necessary the case. Let’s assume Alice and Bob are Centrifuge users who use the account abstraction wallets. Following bad outcomes can happen: 1. Alice wants to send batch, Bob wants to send subsidised msg. Alice’s and Bob’s operations get bundled in the same TX. Bob’s operation will fail (no fuel) because <span style="color:#435489">PaymentMethod.Transaction</span> will be left set after Alice’s operation, even though Bob wanted to use the default subsidised mode. 2. Alice wants to send batch, overpays for the fees. If Alice’s and Bob’s operation end up bundled together Bob can piggyback off of Alice’s leftover fuel and use it to send his message.

### **Recommendation**

Reset all the transient storage vars to their original values.



7

Burra Security

---

<u>Centrifuge Security Review Report</u> | <u>April 25, 2025</u>

## **BurraSec**

Fix in [PR#253](https://github.com/centrifuge/protocol-v3/pull/253) looks good, all transient vars are reset after msg/batch is processed.

## **[I-02] Ensure the correctness of refundWormholeId**

### **Target**

* [WormholeAdapter.sol](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/WormholeAdapter.sol)

### **Severity**

Info

### **Description**

`WormholeAdapter` sets the `refundWormholeId` in the [constructor.](https://github.com/centrifuge/protocol-v3/blob/17d58277fda7199dcef1960f966b2211f8258754/src/common/WormholeAdapter.sol#L28) That should always be the wormhole ID of the current chain, because refund address is the Centrifuge gateway of that chain. In order to avoid misinterpreting the `refundWormholeId` it could be automatically fetched on-chain: `relayer` -> `getDefaultDeliveryProvider()` -> `chainId()`. Alternatively, you could add docs/comments clarifying that `refundWormholeId` should always be the current chain.

Fix in [PR#253](https://github.com/centrifuge/protocol-v3/pull/253) looks good

## **[I-03] Mismatch between SendProof and ProcessProof events**

### **Target**

* [Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/af76d5a74c9c575572c66e4a1c10ba1b182032f5/src/common/Gateway.sol)

### **Severity**

INFO

Burra Security | 8

---

<u>Centrifuge Security Review Report</u> <u>April 25, 2025</u>

## **Description**

Events SendProof and ProcessProof are used to track and match messages between source and destination chain. But there is a mismatch - sending will emit serialized proof, while receiving will emit deserialized proof (hash without the prefix). Same format should be used for consistency and to avoid issues in off-chain processing.

## **Client**

Fixed by [#260](https://github.com/centrifuge/protocol-v3/pull/260/files#diff-a3151d4a260fe43864938f76409b81f19506a82eeee19fefcbb5ce5912fd4370R318)

## **BurraSec**

Fix looks good

Burra Security 9