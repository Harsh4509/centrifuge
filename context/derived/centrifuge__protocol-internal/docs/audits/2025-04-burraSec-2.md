![logo: BURRA SEC wordmark](page_1_image_1_v2.jpg)


# **Centrifuge Security Review**


Reviewed by: Goran Vladika, Pranav Garg

22nd April - 25th April, 2025

---

Centrifuge Security Review Report April 29, 2025

# Centrifuge Security Review Report

Burra Security

April 29, 2025


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

<u>Centrifuge Security Review Report</u> <u>April 29, 2025</u>

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


***review commit hash*** - **[efcf3bcdbbeaca913d4240aade6e99c8a9bff7c6](https://github.com/centrifuge/protocol-v3/blob/efcf3bcdbbeaca913d4240aade6e99c8a9bff7c6/)**


### **Scope**


The following smart contracts were in the scope of the audit:

- [src/common/Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/efcf3bcdbbeaca913d4240aade6e99c8a9bff7c6/src/common/Gateway.sol)
- [src/misc/libraries/TransientBytesLib.sol](https://github.com/centrifuge/protocol-v3/blob/efcf3bcdbbeaca913d4240aade6e99c8a9bff7c6/src/misc/libraries/TransientBytesLib.sol)
- [src/misc/libraries/TransientArrayLib.sol](https://github.com/centrifuge/protocol-v3/blob/efcf3bcdbbeaca913d4240aade6e99c8a9bff7c6/src/misc/libraries/TransientArrayLib.sol)

Burra Security 3

---

<u>Centrifuge Security Review Report</u>
<u>April 29, 2025</u>

## **Findings Summary**

<table>
<thead>
<tr><th>ID</th><th>Title</th><th>Severity</th><th>Status</th></tr>
</thead>
<tbody>
<tr><td>C-01</td><td>Attacker can use re-entrancy to drain the Gateway</td><td>Critical</td><td>Resolved</td></tr>
<tr><td>M-01</td><td>Underpaid messages can’t be submitted</td><td>Medium</td><td>Resolved</td></tr>
<tr><td>L-01</td><td>Only one duplicated message can be in recovery process at a time</td><td>Low</td><td>Ack</td></tr>
<tr><td>I-01</td><td>Mark more event fields as indexed</td><td>Info</td><td>Resolved</td></tr>
<tr><td>I-02</td><td>Skip pulling funds from escrow if it is empty</td><td>Info</td><td>Resolved</td></tr>
</tbody>
</table>

## **Detailed Findings**

### **[C-01] Attacker can use re-entrancy to drain the Gateway**

#### **Target**

- [Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/efcf3bcdbbeaca913d4240aade6e99c8a9bff7c6/src/common/Gateway.sol)

#### **Severity:**

- Impact: High
- Likelihood: High

#### **Description:**

There is a critical re-entrancy vulnerability in Gateway’s implementation of TX refund:

```solidity
function _refundTransaction() internal {
    if (transactionRefund == address(0)) return;

    if (fuel > 0) {
        (bool success,) = payable(transactionRefund).call{value: fuel}(new bytes(0));

        if (!success) {
            // If refund fails, move remaining fuel to global pot
            _subsidizePool(GLOBAL_POT, transactionRefund, fuel);
```



4

Burra Security

---

<u>Centrifuge Security Review Report</u>
<u>April 29, 2025</u>

```solidity
            }

            fuel = 0;
        }

            transactionRefund = address(0);
    }
```

The core of the issue is that the external call to the untrusted party is performed **before** transient state is updated. So contract set as <span style="color:#435489">`transactionRefund`</span> can re-enter the batch processing process and get the refund again, and again, until the Gateway is drained. Gateway holds the subsidy funds, so all of those would be lost. Additionally, attacker can craft the messages to pull in all the funds from the escrows and then steal those funds as well.

Let's say Gateway holds 100 ETH. Here's how attack could look like:

- attacker crafts exploit contract which can trigger the batch process by calling ie. <span style="color:#435489">`VaultRouter`</span>'s <span style="color:#435489">`multicall`</span>
- batch costs 0.1 ETH but attacker provides 20.1 ETH
- flow goes <span style="color:#435489">`startBatching`</span> -> <span style="color:#435489">`payTransaction`</span> -> multiple <span style="color:#435489">`send`</span>s -> <span style="color:#435489">`endBatching`</span> -> <span style="color:#435489">`_refundTransaction`</span>
- when <span style="color:#435489">`_refundTransaction`</span> is started, <span style="color:#435489">`isBatching`</span> = false, <span style="color:#435489">`fuel`</span> = 20ETH
- attacker's exploit contract is called to refund 20 ETH
- exploit contract receives 20 ETH and triggers the batch process again by calling <span style="color:#435489">`multicall`</span>, this time providing 0 value
- batch is processed, refund is triggered while <span style="color:#435489">`fuel`</span> is still set at 20 ETH. Attacker receives 20 ETH again
- attacker's exploit contract repeats this process 5 times
- at the end, attacker holds 120 ETH (20 ETH from the initial overpayment and 100 ETH drained from Gateway)

This attack is also valid when sending a single message (not necessarily a batch).

## **Recommendation:**

Update transient state (<span style="color:#435489">`fuel`</span> and <span style="color:#435489">`transactionRefund`</span>) before doing the external call.

Burra Security

---

<u>Centrifuge Security Review Report</u> <u>April 29, 2025</u>

**Client:**

Fixed in <span style="color:#435489">[PR</span>#300](https://github.com/centrifuge/protocol-v3/pull/300)

**BurraSec:**

Fix looks good

## [M-02] Underpaid messages can’t be submitted

**Target**

- [Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/efcf3bcdbbeaca913d4240aade6e99c8a9bff7c6/src/common/Gateway.sol)

**Severity:**

- Impact: Medium
- Likelihood: Medium

**Description:**

Centrifuge lets users and external protocols to submit batches without paying for them. The goal is to let pool issuer to pay for submitted underpaid batches separately when needed. This approach works with Axelar adapter. Axelar supports requesting a cross-chain message and then paying for it separately. But Wormhole does not support it. Wormhole adapter calls <span style="color:#435489">`sendPayloadToEvm`</span> on the relayer. Relayer will check if provided value matches the actual cost for delivering, and if that’s not the case TX will revert. Thus message cannot be submitted without being paid for, breaking the use-case which is supposed to be supported.

**Recommendation:**

Add logic on the gateway side to store underpaid messages and to enable separate payments for transferring them.

**Client:**

Fixed in [PR#300](https://github.com/centrifuge/protocol-v3/pull/300)



6

Burra Security

---

<u>Centrifuge Security Review Report</u> <u>April 29, 2025</u>

**BurraSec:**


Fix looks good, submission of underpaid msgs is now supported


# **[L-01] Only one duplicated message can be in recovery process at a time**


## **Target**


- [Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/efcf3bcdbbeaca913d4240aade6e99c8a9bff7c6/src/common/Gateway.sol)


## **Severity:**


- Impact: Medium


- Likelihood: Low


## **Description:**


Centrifuge supports processing of identical messages. There are no nonces, so counters are used to keep track of duplicated messages, ie:


```solidity
bytes32 messageHash = keccak256(message);
failedMessages[centrifugeId][messageHash]++;
emit FailMessage(centrifugeId, message, err);
```


There is also a recovery mechanism which can be used by admin to recover lost messages:


```solidity
function initiateRecovery(uint16 centrifugeId, IAdapter adapter,
    bytes32 payloadHash) external auth {
    require(_activeAdapters[centrifugeId][adapter].id != 0,
        InvalidAdapter());
    recoveries[centrifugeId][adapter][payloadHash] = block.
        timestamp + RECOVERY_CHALLENGE_PERIOD;
    emit InitiateRecovery(centrifugeId, payloadHash, adapter);
}
```


One issue with this implementation is that it lacks support to handle recovery of multiple identical messages at a time. If `initiateRecovery` is called for a message, when recovery of identical message is already ongoing, result will be delaying the recovery of a single message. Second identical message can be recovered only when 1st one is executed.



7

Burra Security

---

<u>Centrifuge Security Review Report</u>

<u>April 29, 2025</u>

**Recommendation:**

If this edge case seems realistic enough, consider using counter-based approach for recoveries in addition to timestamps.

**Client:**

Acknowledged, this is by design.

**BurraSec:**

Acknowledged

## [I-01] Mark more event fields as `indexed`

**Target**

- `<span style="color:#435489">[IGateway.sol](https://github.com/centrifuge/protocol-v3/blob/efcf3bcdbbeaca913d4240aade6e99c8a9bff7c6/src/common/interfaces/IGateway.sol)</span>`

**Severity:**

INFO

**Description:**

Having certain event fields marked as <span style="color:#435489">`indexed`</span> enables straight-forward way for searching or filtering events by that field. Ie. it could be useful to mark <span style="color:#435489">`payloadId`</span> as <span style="color:#435489">`indexed`</span> in all events, so that a single <span style="color:#435489">`eth_getLogs`</span> can fetch all the event data for a specific batch. Similarly, marking <span style="color:#435489">`underpaid`</span> field as `indexed` enables having a simple call to track all batches which need manual intervention.

**Client:**

Fixed in `[PR#300](https://github.com/centrifuge/protocol-v3/pull/300)`



8

Burra Security

---

<u>Centrifuge Security Review Report</u> <u>April 29, 2025</u>

**BurraSec:**


Fix looks good


# **[I-02] Skip pulling funds from escrow if it is empty**


## **Target**


- [Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/efcf3bcdbbeaca913d4240aade6e99c8a9bff7c6/src/common/Gateway.sol)


**Severity:**


INFO


**Description:**


Gateway has logic to fetch funds from escrow if current subsidy amount is not big enough:


```solidity
    function _requestPoolFunding(PoolId poolId) internal {
        IRecoverable refund = subsidy[poolId].refund;
        if (!poolId.isNull() && address(refund) != address(0)) {
            uint256 refundBalance = address(refund).balance;

            // Send to the gateway GLOBAL_POT
            refund.recoverTokens(ETH_ADDRESS, address(this),
                refundBalance);

            // Extract from the GLOBAL_POT
            subsidy[GLOBAL_POT].value -= uint96(refundBalance);
            _subsidizePool(poolId, address(refund), refundBalance);
        }
    }
```


It’s reasonably likely that escrow might be empty, so in case `refundBalance` is 0 early return would save gas on unnecessary external call and multiple storage operations.


**Client:**


Fixed in `[PR#300](https://github.com/centrifuge/protocol-v3/pull/300)`



9

Burra Security

---

<u>Centrifuge Security Review Report</u> <u>April 29, 2025</u>

**BurraSec:**

Fix looks good



10

Burra Security