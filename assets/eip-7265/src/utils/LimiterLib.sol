// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Limiter, LiqChangeNode} from "../static/Structs.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {ISettlementModule} from "../interfaces/ISettlementModule.sol";

// BPS = Basis Points : 1 Basis Point is equivalent to 0.01%
uint256 constant BPS_DENOMINATOR = 10000;

enum LimitStatus {
    Uninitialized,
    Inactive,
    Ok,
    Triggered
}

/**
 * @title LimiterLib
 * @dev Set of tools to track a security parameter over a specific time period.
 * @dev It offers tools to record changes, enforce limits based on set thresholds, and maintain a historical view of the security parameter.
 */
library LimiterLib {
    error InvalidMinimumLiquidityThreshold();
    error LimiterAlreadyInitialized();
    error LimiterNotInitialized();

    /**
     * @notice Initialize the limiter
     * @param limiter The limiter to initialize
     * @param minLiqRetainedBps The minimum liquidity that MUST be retained in percent
     * @param limitBeginThreshold The minimal amount of a security parameter that MUST be reached before the Circuit Breaker checks for a breach
     * @param settlementModule The address of the settlement module chosen when the CircuitBreaker triggers
     */
    function init(
        Limiter storage limiter,
        uint256 minLiqRetainedBps,
        uint256 limitBeginThreshold,
        ISettlementModule settlementModule
    ) internal {
        // MUST define a minimum liquidity threshold > 0% and < 100%
        if (minLiqRetainedBps == 0 || minLiqRetainedBps > BPS_DENOMINATOR) {
            revert InvalidMinimumLiquidityThreshold();
        }
        if (isInitialized(limiter)) revert LimiterAlreadyInitialized();
        limiter.minLiqRetainedBps = minLiqRetainedBps;
        limiter.limitBeginThreshold = limitBeginThreshold;
        limiter.settlementModule = settlementModule;
    }

    /**
     * @notice Update the limiter parameters
     * @param limiter The limiter to update
     * @param minLiqRetainedBps The minimum liquidity that MUST be retained in percent
     * @param limitBeginThreshold The minimal amount of a security parameter that MUST be reached before the Circuit Breaker checks for a breach
     * @param settlementModule The address of the settlement module chosen when the CircuitBreaker triggers
     */
    function updateParams(
        Limiter storage limiter,
        uint256 minLiqRetainedBps,
        uint256 limitBeginThreshold,
        ISettlementModule settlementModule
    ) internal {
        if (minLiqRetainedBps == 0 || minLiqRetainedBps > BPS_DENOMINATOR) {
            revert InvalidMinimumLiquidityThreshold();
        }
        if (!isInitialized(limiter)) revert LimiterNotInitialized();
        limiter.minLiqRetainedBps = minLiqRetainedBps;
        limiter.limitBeginThreshold = limitBeginThreshold;
        limiter.settlementModule = settlementModule;
    }

    /**
     * @notice Record a change in the security parameter
     * @param limiter The limiter to record the change for
     * @param amount The amount of the change
     * @param withdrawalPeriod The period over which the change is recorded
     * @param tickLength Unit of time to consider in seconds
     */
    function recordChange(
        Limiter storage limiter,
        int256 amount,
        uint256 withdrawalPeriod,
        uint256 tickLength
    ) internal {
        // If token does not have a rate limit, do nothing
        if (!isInitialized(limiter)) {
            return;
        }

        // all transactions that occur within a given tickLength will have the same currentTickTimestamp
        uint256 currentTickTimestamp = getTickTimestamp(
            block.timestamp,
            tickLength
        );
        limiter.liqInPeriod += amount;

        uint256 listHead = limiter.listHead;
        if (listHead == 0) {
            // if there is no head, set the head to the new inflow
            limiter.listHead = currentTickTimestamp;
            limiter.listTail = currentTickTimestamp;
            limiter.listNodes[currentTickTimestamp] = LiqChangeNode({
                amount: amount,
                nextTimestamp: 0
            });
        } else {
            // if there is a head, check if the new inflow is within the period
            // if it is, add it to the head
            // if it is not, add it to the tail
            if (block.timestamp - listHead >= withdrawalPeriod) {
                sync(limiter, withdrawalPeriod);
            }

            // check if tail is the same as block.timestamp (multiple txs in same block)
            uint256 listTail = limiter.listTail;
            if (listTail == currentTickTimestamp) {
                // add amount
                limiter.listNodes[currentTickTimestamp].amount += amount;
            } else {
                // add to tail
                limiter
                    .listNodes[listTail]
                    .nextTimestamp = currentTickTimestamp;
                limiter.listNodes[currentTickTimestamp] = LiqChangeNode({
                    amount: amount,
                    nextTimestamp: 0
                });
                limiter.listTail = currentTickTimestamp;
            }
        }
    }

    /**
     * @notice Sync the limiter
     * @param limiter The limiter to sync
     * @param withdrawalPeriod the max period to keep track of
     */
    function sync(Limiter storage limiter, uint256 withdrawalPeriod) internal {
        sync(limiter, withdrawalPeriod, type(uint256).max);
    }

    /**
     * @notice Sync the limiter to clear old data
     * @param limiter The limiter to sync
     * @param withdrawalPeriod the max period to keep track of
     * @param totalIters the max number of iterations to perform
     */
    function sync(
        Limiter storage limiter,
        uint256 withdrawalPeriod,
        uint256 totalIters
    ) internal {
        uint256 currentHead = limiter.listHead;
        int256 totalChange = 0;
        uint256 iter = 0;

        while (
            currentHead != 0 &&
            block.timestamp - currentHead >= withdrawalPeriod &&
            iter < totalIters
        ) {
            LiqChangeNode storage node = limiter.listNodes[currentHead];
            totalChange += node.amount;
            uint256 nextTimestamp = node.nextTimestamp;
            // Clear data
            limiter.listNodes[currentHead];
            currentHead = nextTimestamp;
            // forgefmt: disable-next-item
            unchecked {
                ++iter;
            }
        }

        if (currentHead == 0) {
            // If the list is empty, set the tail and head to current times
            limiter.listHead = block.timestamp;
            limiter.listTail = block.timestamp;
        } else {
            limiter.listHead = currentHead;
        }
        limiter.liqTotal += totalChange;
        limiter.liqInPeriod -= totalChange;
    }

    /**
     * @notice Get the status of the limiter
     * @param limiter The limiter to get the status for
     * @return The status of the limiter
     */
    function status(
        Limiter storage limiter
    ) internal view returns (LimitStatus) {
        if (!isInitialized(limiter)) {
            return LimitStatus.Uninitialized;
        }
        if (limiter.overriden) {
            return LimitStatus.Ok;
        }

        int256 currentLiq = limiter.liqTotal;

        // Only enforce rate limit if there is significant liquidity
        if (limiter.limitBeginThreshold > uint256(currentLiq)) {
            return LimitStatus.Inactive;
        }

        int256 futureLiq = currentLiq + limiter.liqInPeriod;
        // NOTE: uint256 to int256 conversion here is safe
        int256 minLiq = (currentLiq * int256(limiter.minLiqRetainedBps)) /
            int256(BPS_DENOMINATOR);

        return futureLiq < minLiq ? LimitStatus.Triggered : LimitStatus.Ok;
    }

    /**
     * @notice Get the current liquidity
     * @param limiter The limiter to get the liquidity for
     * @return Has the minLiqRetainedBps of the Limiter been set ?
     */
    function isInitialized(
        Limiter storage limiter
    ) internal view returns (bool) {
        return limiter.minLiqRetainedBps > 0;
    }

    /**
        * @notice Get the timestamp for the current period (as defined by ticklength)
        * @param t The current timestamp
        * @param tickLength The tick length
        * @return The current tick timestamp
        */
     */
    function getTickTimestamp(
        uint256 t,
        uint256 tickLength
    ) internal pure returns (uint256) {
        return t - (t % tickLength);
    }
}
