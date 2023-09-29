// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ISettlementModule} from "../interfaces/ISettlementModule.sol";

/**
 * @notice LiqChangeNode struct
 */
struct LiqChangeNode {
    uint256 nextTimestamp;
    int256 amount;
}


/**
 * @notice Limiter struct
 * A limiter specifies the configuration and data stored for a security paramter
 * @dev This struct lines out the storage structure of a limiter for the CircuitBreaker.
 */
struct Limiter {
    /// @notice The minimum liquidity that MUST be retained in percent
    uint256 minLiqRetainedBps;
    /// @notice The minimal absolute amount of a security parameter that MUST be reached before the Circuit Breaker checks for a breach
    uint256 limitBeginThreshold;
    /// @notice The current value of the security parameter
    int256 liqTotal;
    /// @notice The current value change of the security parameter within the current period
    int256 liqInPeriod;
    /// @notice The latest value of the security parameter within the current period
    uint256 listHead;
    /// @notice The earliest value of the security parameter within the current period
    uint256 listTail;
    /// @notice The list of value changes of the security parameter
    mapping(uint256 tick => LiqChangeNode node) listNodes;
    /// @notice The address of the settlement module chosen when the CircuitBreaker triggers
    ISettlementModule settlementModule;
    /// @notice Whether the limiter has been manually overriden
    bool overriden;
}
