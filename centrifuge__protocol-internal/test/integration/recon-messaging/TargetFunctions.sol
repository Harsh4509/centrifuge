// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {FailoverTargets} from "./targets/FailoverTargets.sol";
import {MessagingProperties} from "./properties/MessagingProperties.sol";

/// @dev FailoverTargets pulls in StandbyTargets, GatewayTargets and MultiAdapterTargets transitively.
abstract contract TargetFunctions is FailoverTargets, MessagingProperties {}
