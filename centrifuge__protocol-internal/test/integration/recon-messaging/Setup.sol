// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {BatcherActor} from "./mocks/BatcherActor.sol";
import {ManagerActor} from "./mocks/ManagerActor.sol";
import {StewardActor} from "./mocks/StewardActor.sol";
import {SimpleAdapter} from "./mocks/SimpleAdapter.sol";
import {MockMessageGas} from "./mocks/MockMessageGas.sol";
import {MockProtocolPauser} from "./mocks/MockProtocolPauser.sol";
import {CountingProcessor, POOL_A as MOCK_POOL_A, POOL_B as MOCK_POOL_B} from "./mocks/CountingProcessor.sol";

import {PoolId} from "../../../src/core/types/PoolId.sol";
import {Gateway} from "../../../src/core/messaging/Gateway.sol";
import {MultiAdapter} from "../../../src/core/messaging/MultiAdapter.sol";
import {IAdapter} from "../../../src/core/messaging/interfaces/IAdapter.sol";
import {IAdapterEntrypoint} from "../../../src/core/messaging/interfaces/IAdapterEntrypoint.sol";

import {AdapterFailover} from "../../../src/managers/adapters/AdapterFailover.sol";
import {IAdapterFailover} from "../../../src/managers/adapters/interfaces/IAdapterFailover.sol";

import {BaseSetup} from "@chimera/BaseSetup.sol";
import {StandbyAdapter} from "../../../src/adapters/StandbyAdapter.sol";

abstract contract Setup is BaseSetup {
    error BucketsMustFrameAsOneByteMessages();

    uint16 internal constant LOCAL_CENTRIFUGE_ID = 1;
    uint16 internal constant REMOTE_CENTRIFUGE_ID = 2;

    uint8 internal constant ADAPTER_COUNT = 3;
    uint8 internal constant THRESHOLD = 2;

    // Payload keyspace bound: collapse fuzzed payloads into this many canonical single-byte
    // representatives so independent handler calls collide on the same (cId, hash) key.
    uint8 internal constant PAYLOAD_BUCKETS = 16;

    PoolId internal constant GLOBAL_POOL = PoolId.wrap(0);
    // Second configured pool, and a pool left unconfigured so its `SetPoolAdapters` travels over the
    // global set until its first `setAdapters`. Payloads pick their pool through CountingProcessor.
    PoolId internal constant POOL_A = MOCK_POOL_A;
    PoolId internal constant POOL_B = MOCK_POOL_B;
    uint8 internal constant POOL_COUNT = 3;

    Gateway internal gateway;
    MultiAdapter internal multiAdapter;

    CountingProcessor internal countingProcessor;
    MockMessageGas internal mockMessageGas;
    MockProtocolPauser internal mockProtocolPauser;

    // Adapters: deliver() is the inbound entrypoint for the fuzzer
    SimpleAdapter internal adapter0;
    SimpleAdapter internal adapter1;
    SimpleAdapter internal adapter2;

    // A real StandbyAdapter over its dedicated underlying adapter. In no set until
    // `multiAdapter_reconfigureWithStandby` installs it; inbound reaches it only through `underlying`.
    StandbyAdapter internal standby;
    SimpleAdapter internal underlying;

    /// @dev What Gateway hands adapters as the gas limit: the sum of `messageOverallGasLimit`, which the mock
    ///      fixes at 0. A standby credit is keyed on it, so the harness can name every credit it caused.
    uint256 internal constant DISPATCH_GAS_LIMIT = 0;

    // Non-ward second actor for the pool-manager path (role granted/revoked via updateManager)
    ManagerActor internal managerActor;

    // Outbound-batching initiators: withBatch calls back into msg.sender, so this cannot be the test
    // contract. `batcher` is a gateway ward (it calls the auth-gated send); `batcherPeer` is the
    // non-batcher caller for the CallbackWasNotFromSender negative and needs no ward.
    BatcherActor internal batcher;
    BatcherActor internal batcherPeer;

    // A real AdapterFailover. The test contract is its envoy (the hub's `fromHub` caller) and `stewardActor`
    // the steward. It holds the MultiAdapter manager role on the two non-global pools only: the hub never
    // stewards the global set, and `failover_updateManager` toggles the role.
    uint64 internal constant FAILOVER_TIMELOCK = 2 days;
    AdapterFailover internal failover;
    StewardActor internal stewardActor;

    function setup() internal virtual override {
        mockMessageGas = new MockMessageGas();
        mockProtocolPauser = new MockProtocolPauser();
        countingProcessor = new CountingProcessor();

        gateway = new Gateway(LOCAL_CENTRIFUGE_ID, mockProtocolPauser, address(this));
        multiAdapter = new MultiAdapter(LOCAL_CENTRIFUGE_ID, gateway, address(this));

        adapter0 = new SimpleAdapter(REMOTE_CENTRIFUGE_ID, multiAdapter);
        adapter1 = new SimpleAdapter(REMOTE_CENTRIFUGE_ID, multiAdapter);
        adapter2 = new SimpleAdapter(REMOTE_CENTRIFUGE_ID, multiAdapter);

        underlying = new SimpleAdapter(REMOTE_CENTRIFUGE_ID, IAdapterEntrypoint(address(0)));
        standby = new StandbyAdapter(multiAdapter, underlying);
        underlying.setEntrypoint(standby);

        managerActor = new ManagerActor(multiAdapter, gateway); // starts WITHOUT either manager role

        batcher = new BatcherActor(gateway);
        batcherPeer = new BatcherActor(gateway);
        batcher.setPeer(batcherPeer);

        gateway.file("processor", address(countingProcessor));
        gateway.file("messageGas", address(mockMessageGas));
        gateway.file("adapter", address(multiAdapter));

        multiAdapter.file("parser", address(countingProcessor));
        multiAdapter.file("messageGas", address(mockMessageGas));

        IAdapter[] memory addrs = new IAdapter[](ADAPTER_COUNT);
        addrs[0] = IAdapter(address(adapter0));
        addrs[1] = IAdapter(address(adapter1));
        addrs[2] = IAdapter(address(adapter2));
        // Session 1: neither pool has been configured, so the next session id is always 1. The identical
        // sets keep single-pool reasoning valid until the fuzzer reconfigures one of them.
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, addrs, THRESHOLD, 1);
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, POOL_A, addrs, THRESHOLD, 1);

        // Bucketed payloads double as one-byte messages in a multi-message batch.
        require(countingProcessor.ONE_BYTE_BELOW() == PAYLOAD_BUCKETS, BucketsMustFrameAsOneByteMessages());

        // Auth: multiAdapter must be a ward of gateway so it can call gateway.handle()
        gateway.rely(address(multiAdapter));

        // Auth: gateway must be a ward of multiAdapter so it can call multiAdapter.send() on outbound
        multiAdapter.rely(address(gateway));

        // Auth: the batching actor issues gateway.send() from inside the withBatch callback, and send is
        // `auth`. This is additive to the test-contract-as-ward layout, not a replacement for it.
        gateway.rely(address(batcher));

        // The failover needs the wired MultiAdapter, so it comes after the wiring above.
        failover = new AdapterFailover(address(this), multiAdapter, FAILOVER_TIMELOCK);
        stewardActor = new StewardActor(failover);
        multiAdapter.updateManager(POOL_A, address(failover), true);
        multiAdapter.updateManager(POOL_B, address(failover), true);
        failover.fromHub(POOL_A, abi.encode(uint8(IAdapterFailover.HubCall.UpdateSteward), stewardActor, true));
    }

    /// @dev The pools a failover can target: the hub assigns stewards per pool and never for the global set.
    function _failoverPoolAt(uint8 seed) internal pure returns (PoolId) {
        return seed % 2 == 0 ? POOL_A : POOL_B;
    }

    /// @dev Collapse a fuzzed payload into one of PAYLOAD_BUCKETS canonical single-byte payloads so independent
    ///      handler calls collide on one (cId, hash); without it the fail -> retry/clear cycle is unreachable.
    ///      Idempotent, so Foundry tests can bucket once and keep hashing the raw payload.
    function _bucket(bytes memory payload) internal pure returns (bytes memory) {
        if (payload.length == 1 && uint8(payload[0]) < PAYLOAD_BUCKETS) return payload;
        return abi.encodePacked(uint8(uint256(keccak256(payload)) % PAYLOAD_BUCKETS));
    }

    function _poolAt(uint8 seed) internal pure returns (PoolId) {
        uint8 i = seed % POOL_COUNT;
        return i == 0 ? GLOBAL_POOL : (i == 1 ? POOL_A : POOL_B);
    }

    /// @dev The pool whose adapter set carries `payload` right now, mirroring `MultiAdapter._routePoolId`.
    ///      Read live: a fallback payload moves from the global set to POOL_B at POOL_B's first configuration.
    function _route(bytes memory payload) internal view returns (PoolId) {
        PoolId poolId = countingProcessor.messagePoolId(payload);
        bool poolConfigured = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, poolId) != 0;
        return countingProcessor.routePoolId(payload, poolConfigured);
    }

    /// @dev Prefix a payload with its routed pool's 2-byte active session id, mirroring MultiAdapter.send().
    ///      Inbound handle/vote/execute resolve the adapter set from `payload[0:2]`: unwrapped reverts
    ///      InvalidAdapter.
    function _wrap(bytes memory payload) internal view returns (bytes memory) {
        return _wrapAt(_route(payload), payload);
    }

    /// @dev `_wrap` for a caller that already holds the routed pool, which saves `_route`'s three external calls.
    function _wrapAt(PoolId routedPool, bytes memory payload) internal view returns (bytes memory) {
        return abi.encodePacked(multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, routedPool), payload);
    }

    /// @dev `MultiAdapter._votes` is keyed by `keccak256(routedPoolId ++ wrappedPayload)`, not by the bare wrapped
    ///      hash. The width is load-bearing: `PoolId.raw()` is a `uint64`, so the prefix is 8 bytes; a 32-byte
    ///      prefix addresses an empty slot and silently makes every vote-reading property vacuous.
    function _voteKey(PoolId routedPool, bytes memory wrappedPayload) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(routedPool.raw(), wrappedPayload));
    }

    /// @dev Live active adapter set, never mirrored in a ghost: reconfigure can install non-prefix sets.
    function _activeList(PoolId poolId) internal view returns (IAdapter[] memory) {
        return multiAdapter.activeAdapters(REMOTE_CENTRIFUGE_ID, poolId).list;
    }

    /// @dev The contract that delivers inbound for set member `adapter`. The standby has no deliver of its own:
    ///      its votes arrive through `underlying`, the only caller it accepts.
    function _inbound(IAdapter adapter) internal view returns (SimpleAdapter) {
        return SimpleAdapter(address(adapter) == address(standby) ? address(underlying) : address(adapter));
    }

    /// @dev Times `adapter` has been sent exactly these wrapped bytes. For the standby that is its outstanding
    ///      credit, which only a `forward` lowers, so it reads as a send count within one handler.
    function _sentCount(IAdapter adapter, bytes memory wrapped) internal view returns (uint256) {
        if (address(adapter) == address(standby)) return standby.forwardable(_standbyId(wrapped));
        return SimpleAdapter(address(adapter)).sentCount(keccak256(wrapped));
    }

    function _standbyId(bytes memory wrapped) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(REMOTE_CENTRIFUGE_ID, DISPATCH_GAS_LIMIT, wrapped));
    }

    function _isActive(PoolId poolId, address adapter) internal view returns (bool) {
        return _contains(_activeList(poolId), adapter);
    }

    function _contains(IAdapter[] memory list, address adapter) internal pure returns (bool) {
        for (uint256 i; i < list.length; i++) {
            if (address(list[i]) == adapter) return true;
        }
        return false;
    }
}
