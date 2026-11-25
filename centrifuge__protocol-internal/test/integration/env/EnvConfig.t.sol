// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ContractsConfig, Env} from "../../../script/utils/EnvConfig.s.sol";
import {ChainConfig, Chains} from "../../../script/utils/ChainConfig.s.sol";

import "forge-std/Test.sol";

import {ChainConfigBase} from "../chain/ChainConfig.t.sol";
import {FullDeploymentConfigTest} from "../Deployer.t.sol";

/// @dev That every config resolves the peers it is wired to, which is a property of the pair — a connections
///      file naming a network that is gone, or a peer whose centrifugeId no longer fits the 32-slot array,
///      fails here. Each config is read under the deployment it sits in, and its peers follow it there on
///      their own: the connections file is that deployment's, so `buildBatchLimits` reads them from the same
///      directory rather than by bare name. Empty on a branch holding no configs, like the rest of the
///      directory-driven rules.
contract EnvConnectionsTest is ChainConfigBase {
    function test_everyConfigResolvesItsConnections() public view {
        ConfigRef[] memory configs = _configs();

        for (uint256 i; i < configs.length; i++) {
            Chains.load(configs[i].name, configs[i].environment).network.buildBatchLimits();
        }
    }
}

/// @dev Why a launch reads the Root off the chain half. Until a release is deployed, a live config records
///      `contracts.root` and nothing else — the shape a launch onto an existing Root is handed — and
///      `Env.parseContracts` requires every other address, so it rejects those configs outright.
contract EnvRootIsReadOffTheChainHalfTest is Test {
    /// @dev An `env/<environment>/<network>.json` as live carries them before its release is deployed
    string constant ROOT_ONLY = '{"contracts":{"root":{'
        '"address":"0x7Ed48C31f2fdC40d37407cBaBf0870B2b688368f","blockNumber":22924235,"version":"3"}}}';

    function test_theChainHalfAnswersWithTheRecordedRoot() public view {
        assertEq(Chains.parseRootAddress(ROOT_ONLY), 0x7Ed48C31f2fdC40d37407cBaBf0870B2b688368f);
    }

    function test_theContractsHalfCannotReadTheSameConfig() public {
        vm.expectRevert();
        this.parseContracts();
    }

    /// @dev An external hop, so that `vm.expectRevert` sees the revert below its own call
    function parseContracts() external view returns (ContractsConfig memory) {
        ChainConfig memory nothingDeclared;
        return Env.parseContracts(ROOT_ONLY, nothingDeclared);
    }
}

/// @dev The one thing that holds `ContractsConfig` to reality on this branch. `Env.load` describes what a
///      deployment writes, not what any chain is running, so no config in `env/` can prove it — the configs
///      there record earlier releases and are expected to be rejected. What can prove it is a deployment:
///      run one, take the `.contracts` object it would have written, and require the parser to read it.
///
///      A contract required by `ContractsConfig` and never registered makes every config the deployer
///      writes fail to load — the strict parse below reverts on the missing key. The other direction needs
///      its own assertion, because the parser reads the keys it names and never enumerates the JSON: a
///      contract registered by the deployer with no `ContractsConfig` field would parse fine and be
///      silently unreadable from every script. The count pins that; updating it is the act of
///      acknowledging a schema change. What neither covers is a wrong key→field binding
///      (`config.holdings = _required(json, "accounting")`) — the spot checks touch four fields, and the
///      rest is the reader's review burden, cheaper than 50 more asserts that would restate the parser.
contract EnvConfigDeploymentRoundTripTest is FullDeploymentConfigTest {
    function test_theParserReadsWhatTheDeployerWrites() public view {
        assertEq(registeredCount(), 68, "a registered contract has no ContractsConfig field");

        string memory json = string.concat('{"contracts":', registeredContractsJson(), "}");

        ContractsConfig memory contracts = Env.parseContracts(json, _everythingDeclared());

        assertEq(contracts.root, address(root), "root");
        assertEq(contracts.spoke, address(spoke), "spoke");
        assertEq(contracts.hub, address(hub), "hub");
        assertEq(contracts.vaultFactory, address(vaultFactory), "vaultFactory");
        assertEq(contracts.orderBook, address(orderBook), "orderBook");
        assertEq(contracts.layerZeroAdapter, address(layerZeroAdapter), "layerZeroAdapter");
        assertEq(contracts.axelarStandby, address(axelarStandby), "axelarStandby");
        assertEq(contracts.axelarStandbyUnderlying, address(axelarStandby.underlying()), "axelarStandbyUnderlying");
    }

    /// @dev The other direction of the adapter rule: an address recorded under a `deploy: false` flag is a
    ///      config contradicting itself, and must refuse to parse rather than hand readers `address(0)` for
    ///      a contract the file plainly names.
    function test_aRecordedAdapterUnderAFalseFlagRefusesToParse() public {
        string memory json = string.concat('{"contracts":', registeredContractsJson(), "}");

        ChainConfig memory chain = _everythingDeclared();
        chain.adapters.layerZero.deploy = false;

        vm.expectRevert(bytes("chain declares no layerZeroAdapter but the config records one"));
        this.parseContracts(json, chain);
    }

    /// @dev The same rule for the spoke half of the vault stack
    function test_aRecordedVaultStackUnderAFalseFlagRefusesToParse() public {
        string memory json = string.concat('{"contracts":', registeredContractsJson(), "}");

        ChainConfig memory chain = _everythingDeclared();
        chain.network.vaults = false;

        vm.expectRevert(bytes("chain declares no vaultFactory but the config records one"));
        this.parseContracts(json, chain);
    }

    /// @dev An external hop, so that `vm.expectRevert` sees the revert at a lower depth than its own call
    function parseContracts(string memory json, ChainConfig memory chain)
        external
        view
        returns (ContractsConfig memory)
    {
        return Env.parseContracts(json, chain);
    }

    /// @dev Every adapter and the vault stack, because `_input` deploys all of them: the parser requires the
    ///      address of each one the chain half says is deployed, so this is the shape that asks the most of it
    function _everythingDeclared() private pure returns (ChainConfig memory chain) {
        chain.adapters.layerZero.deploy = true;
        chain.adapters.axelar.deploy = true;
        chain.adapters.chainlink.deploy = true;
        chain.adapters.hyperlane.deploy = true;
        chain.network.vaults = true;
    }
}

/// @dev The round trip for a chain that does not take the vault stack: the launch registers none of its
///      spoke half, and the parser reads that config without it, while the hub half is still required.
contract EnvConfigWithoutVaultsRoundTripTest is FullDeploymentConfigTest {
    function setUp() public override {
        vaults_ = false;
        super.setUp();
    }

    function test_theParserReadsALaunchWithoutVaults() public view {
        assertEq(registeredCount(), 58, "the ten spoke-half contracts are not registered");

        string memory json = string.concat('{"contracts":', registeredContractsJson(), "}");
        ContractsConfig memory contracts = Env.parseContracts(json, _adaptersOnly());

        assertEq(contracts.vaultFactory, address(0), "vaultFactory");
        assertEq(contracts.vaultRequestRouter, address(0), "vaultRequestRouter");
        assertEq(contracts.vaultLiquidityRoute, address(0), "vaultLiquidityRoute");
        assertEq(contracts.orderBook, address(orderBook), "orderBook");
        assertEq(contracts.feeRequestManager, address(feeRequestManager), "feeRequestManager");
    }

    /// @dev A chain that claims the vault stack must carry it: the missing key fails the load
    function test_aClaimedVaultStackMustBeRecorded() public {
        string memory json = string.concat('{"contracts":', registeredContractsJson(), "}");

        ChainConfig memory chain = _adaptersOnly();
        chain.network.vaults = true;

        vm.expectRevert();
        this.parseContracts(json, chain);
    }

    function parseContracts(string memory json, ChainConfig memory chain)
        external
        view
        returns (ContractsConfig memory)
    {
        return Env.parseContracts(json, chain);
    }

    function _adaptersOnly() private pure returns (ChainConfig memory chain) {
        chain.adapters.layerZero.deploy = true;
        chain.adapters.axelar.deploy = true;
        chain.adapters.chainlink.deploy = true;
        chain.adapters.hyperlane.deploy = true;
    }
}
