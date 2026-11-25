![logo: BURRA SEC wordmark](page_1_image_1_v2.jpg)


# **Centrifuge(LayerZeroAdapter) Security Review**


Reviewed by: windhustler, Goran Vladika

21st August, 2025

---

Centrifuge(LayerZeroAdapter) Security Review Report August 21, 2025

# Centrifuge(LayerZeroAdapter) Security Review Report


Burra Security

August 21, 2025


## **Introduction**


A time-boxed security review of the **LayerZeroAdapter** built by the Centrifuge team was done by **Burra Security** team, focusing on the security aspects of the smart contracts.


## **Disclaimer**


A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource, and expertise-bound effort where we try to find as many vulnerabilities as possible. We can not guarantee 100% security after the review or even if the review will find any vulnerabilities. Subsequent security reviews, bug bounty programs, and on-chain monitoring are recommended.


## **About Burra Security**


Burra Sec offers security auditing and advisory services with a special focus on cross-chain and inter-operability protocols and their integrations.


## **About LayerZeroAdapter**


The focus on the security review was the <span style="color:#435489">`LayerZeroAdapter`</span> contract that enables cross-chain communication between different blockchains using LayerZeroV2.



2

Burra Security

---

<u>Centrifuge(LayerZeroAdapter) Security Review Report</u>    <u>August 21, 2025</u>

## Severity classification

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

***review commit hash*** **- [ba0e8c5e56b1aa4faf57f07cb044532205bb1909](https://github.com/centrifuge/protocol-v3/blob/ba0e8c5e56b1aa4faf57f07cb044532205bb1909/src/adapters/LayerZeroAdapter.sol)**

### **Scope**

The following smart contracts were in the scope of the audit:

- src/adapters/LayerZeroAdapter.sol



3

Burra Security

---

<u>Centrifuge(LayerZeroAdapter) Security Review Report</u>  <u>August 21, 2025</u>

## Findings Summary


<table>
<thead>
<tr><th>ID</th><th>Title</th><th>Severity</th><th>Status</th></tr>
</thead>
<tbody>
<tr><td>L-01</td><td>LayerZeroAdapter is not compatible with Endpoint that uses Lz<br />tokens</td><td>Low</td><td>Ack</td></tr>
<tr><td>L-02</td><td>LayerZero messages can be forced to enter the failed state</td><td>Low</td><td>Ack</td></tr>
<tr><td>I-01</td><td>Missing zero address checks for delegate and endpoint addresses</td><td>Info</td><td>Resolved</td></tr>
<tr><td>I-02</td><td>Swapped natspec in LZ adapter interface</td><td>Info</td><td>Resolved</td></tr>
<tr><td>I-03</td><td>Default max message size of 10000 bytes could limit the batch size</td><td>Info</td><td>Ack</td></tr>
</tbody>
</table>

## Detailed Findings

### [L-01] LayerZeroAdapter is not compatible with Endpoint that uses Lz tokens

**Target**

- [LayerZeroAdapter.sol](https://github.com/centrifuge/protocol-v3/blob/ba0e8c5e56b1aa4faf57f07cb044532205bb1909/src/adapters/LayerZeroAdapter.sol)

**Severity**

- Impact: High
- Likelihood: Low

**Description**

The <span style="color:#435489">`LayerZeroAdapter`</span> contract is designed to work exclusively with LayerZero's standard <span style="color:#435489">`EndpointV2`</span> contract, which accepts native gas tokens as payment for cross-chain messaging. However, on chains where the native gas token has no value, LayerZero deploys an alternative endpoint called `[EndpointV2Alt](https://github.com/LayerZero-Labs/LayerZero-v2/blob/592625b/packages/layerzero-v2/evm/protocol/contracts/EndpointV2Alt.sol)` that only accepts LZ tokens as payment instead of native tokens.



4

Burra Security

---

<u>Centrifuge(LayerZeroAdapter) Security Review Report</u> | <u>August 21, 2025</u>

### **Recommendation**

If you’re planning to deploy on chains that only have the alternative `EndpointV2Alt`, the send logic should handle ERC20 token transfers from the sender’s address to pay for message bridging.

### **Centrifuge**

Acknowledged, we are not planning to deploy on any chains where this is the case.

### **BurraSec**

The issue has been acknowledged.

## **[L-02] LayerZero messages can be forced to enter the failed state**

### **Target**

* [LayerZeroAdapter.sol#L66-L75](https://github.com/centrifuge/protocol-v3/blob/ba0e8c5e56b1aa4faf57f07cb044532205bb1909/src/adapters/LayerZeroAdapter.sol#L66-L75)

### **Severity**

* Impact: Medium
* Likelihood: Low

### **Description**

### **Description**

There is a possibility of DoS with the current function calls where you have:

`LayerZeroAdapter::lzReceive` → `Gateway::handle` → `MessageProcessor::handle`

Since the `LayerZeroAdapter::lzReceive` function only validates that the `msg.sender` is the `Endpoint` contract but doesn’t check the executor of `Endpoint::lzReceive`, once lz messages get verified, anyone can execute them via `EndpointV2::lzReceive` with any gas limit.

Due to EIP-150, only 63/64 of gas is forwarded to external calls. Gateway uses **try**/**catch** for message processing:

Burra Security | 5

---

<u>Centrifuge(LayerZeroAdapter) Security Review Report</u> <u>August 21, 2025</u>

```solidity
try <span style="color:#435489">processor_.handle(centrifugeId, message)</span> {
    <span style="color:#435489">emit ExecuteMessage(centrifugeId, message);</span>
} <span style="color:#435489">catch</span> (<span style="color:#435489">bytes memory err</span>) {
    <span style="color:#435489">bytes32 messageHash = keccak256(message);</span>
    <span style="color:#435489">failedMessages[centrifugeId][messageHash]++;</span>
    <span style="color:#435489">emit FailMessage(centrifugeId, message, err);</span>
}
```


An attacker can execute the following:


1. A legitimate cross-chain message is verified and ready for execution.


2. An attacker calls <span style="color:#435489">`lzReceive`</span>, which calls <span style="color:#435489">`processor_.handle`</span> with just enough gas to:

   - Use the 63/64 gas and cause out-of-gas revert in the **try** block, although the execution should be successful
   - The remaining 1/64 gas is sufficient to execute the catch block, which forces the message into the failed state


**Recommendation**


Use a library from [Optimism and Liquity,](https://github.com/liquity/V2-gov/blob/22bc82f/src/utils/SafeCallMinGas.sol#L4-L13) which you can place before the external call, which ensures that the <span style="color:#435489">`gasleft`</span> is sufficient to execute the external call and if the external call fails due to some logical issue there is still enough gas to execute the catch block.


This approach requires analyzing and setting the appropriate gas amounts required for various message types that are processed inside the <span style="color:#435489">`MessageProcessor`</span>. The gas amount should be sufficient to cover the most gas intensive execution path for each message type.


**Centrifuge**


Seems unlikely but in theory possible! We will fix this by adding the gas library you suggested in the next bigger protocol upgrade.


**BurraSec**


The issue has been acknowledged.



6

Burra Security

---

<u>Centrifuge(LayerZeroAdapter) Security Review Report</u>
<u>August 21, 2025</u>

# [I-01] Missing zero address checks for delegate and endpoint addresses

## **Target**

- [LayerZeroAdapter.sol#L39-L42](https://github.com/centrifuge/protocol-v3/blob/ba0e8c5e56b1aa4faf57f07cb044532205bb1909/src/adapters/LayerZeroAdapter.sol#L39-L42)

## **Severity**

Informational

## **Description**

The <span style="color:#435489">LayerZeroAdapter::setDelegate</span> function lacks zero-address validation for the <span style="color:#435489">newDelegate</span> parameter.

```solidity
## LayerZeroAdapter.sol

function setDelegate(address newDelegate) external auth {
    endpoint.setDelegate(newDelegate); // @audit No zero address
        validation
    emit SetDelegate(newDelegate);
}
```

The LayerZeroV2 OAppCore reference implementation sets the delegate address during contract deployment, which also implicitly checks if the endpoint address is correct.

```solidity
// LayerZero V2 OAppCore reference
constructor(address _endpoint, address _delegate) {
    endpoint = ILayerZeroEndpointV2(_endpoint);

    if (_delegate == address(0)) revert InvalidDelegate();
    endpoint.setDelegate(_delegate);
}
```

## **Recommendation**

Add zero address validation to the <span style="color:#435489">setDelegate</span> function:

```solidity
function setDelegate(address newDelegate) external auth {
+   require(newDelegate != address(0), InvalidDelegate());
    endpoint.setDelegate(newDelegate);
    emit SetDelegate(newDelegate);
}
```



7

Burra Security

---

<u>Centrifuge(LayerZeroAdapter) Security Review Report</u> | <u>August 21, 2025</u>

Additionally, consider setting the delegate in the constructor, following the LayerZero V2 OAppCore implementation.

**Centrifuge**

Fix for setting delegate on constructor is [956ee809312321cccdbb09e5722a8166d1c1fbef](https://github.com/centrifuge/protocol-v3/commit/956ee809312321cccdbb09e5722a8166d1c1fbef)

**BurraSec**

Fix looks good.

## **[I-02] Swapped natspec in LZ adapter interface**

### **Target**

* [ILayerZeroAdapter.sol#L46..L54](https://github.com/centrifuge/protocol-v3/blob/ba0e8c5e56b1aa4faf57f07cb044532205bb1909/src/adapters/interfaces/ILayerZeroAdapter.sol#L46..L54)

### **Severity**

INFO

### **Description**

Natspec comments for `allowInitializePath` and `nextNonce` are swapped.

### **Recommendation**

Adjust the natspec.

**Centrifuge**

Fixed with [43abc7f80ef20152329f215b97e6a4ec5453aaf2](https://github.com/centrifuge/protocol-v3/commit/43abc7f80ef20152329f215b97e6a4ec5453aaf2)

**BurraSec**

Fix looks good.

Burra Security | 8

---

<u>Centrifuge(LayerZeroAdapter) Security Review Report</u>
<u>August 21, 2025</u>

# **[I-03] Default max message size of 10000 bytes could limit the batch size**

## **Target**

- [LayerZeroAdapter.sol#L103](https://github.com/centrifuge/protocol-v3/blob/ba0e8c5e56b1aa4faf57f07cb044532205bb1909/src/adapters/LayerZeroAdapter.sol#L103)

## **Severity**

INFO

## **Description**

The default value of executor's config for max message size is 10\_000 bytes:

```text
  1  cast call -r $ARB $ARB_SEND_LIB <span style="color:#00999a">"executorConfigs(address,uint32) ((</span>
        <span style="color:#00999a">uint32,address))"</span> 0x0000000000000000000000000000000000000000
        $BASE_EID
  2  (10000 [1e4], 0x31CAe3B7fB82d847621859fb1585353c5720660D)
```

If message sent is bigger than that TX will revert on the source chain. Just something to be aware of, in case some future batched payload would grow in size and if limiting the gas on the centrifuge side would not be enough, additional guardrails for batch size could be added.

## **Recommendation**

Test the system with the biggest realistic batch sizes to see if additional limit enforcement is needed.

## **Centrifuge**

Acknowledged, not a feasible limit to hit with the Centrifuge protocol.

## **BurraSec**

Acknowledged



9

Burra Security