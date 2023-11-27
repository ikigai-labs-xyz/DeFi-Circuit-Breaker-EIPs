// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Limiter, LiqChangeNode} from "../static/Structs.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {ISettlementModule} from "../interfaces/ISettlementModule.sol";
import {ICircuitBreaker} from "../interfaces/ICircuitBreaker.sol";
uint256 constant BPS_DENOMINATOR = 10000;

enum LimitStatus {
    Uninitialized,
    Inactive,
    Ok,
    Triggered
}

library LimiterLib {
    error InvalidMinimumLiquidityThreshold();
    error LimiterAlreadyInitialized();
    error LimiterNotInitialized();

    function init(
        bytes32 identifier,
        uint256 minLiqRetainedBps,
        uint256 limitBeginThreshold,
        ISettlementModule settlementModule
    ) internal {
        if (minLiqRetainedBps == 0 || minLiqRetainedBps > BPS_DENOMINATOR) {
            revert InvalidMinimumLiquidityThreshold();
        }

        if (isInitialized(identifier)) revert LimiterAlreadyInitialized();

        ICircuitBreaker(msg.sender).addSecurityParameter(identifier, minLiqRetainedBps, limitBeginThreshold, address(settlementModule));
    }

    function updateParams(
        bytes32 identifier,
        uint256 minLiqRetainedBps,
        uint256 limitBeginThreshold,
        ISettlementModule settlementModule
    ) internal {
        if (minLiqRetainedBps == 0 || minLiqRetainedBps > BPS_DENOMINATOR) {
            revert InvalidMinimumLiquidityThreshold();
        }

        if (!isInitialized(identifier)) revert LimiterNotInitialized();

        ICircuitBreaker(msg.sender).updateSecurityParameter(
            identifier,
            minLiqRetainedBps,
            limitBeginThreshold,
            address(settlementModule)
        );
    }

    function recordChange(
        bytes32 identifier,
        int256 amount,
        uint256 withdrawalPeriod,
        uint256 tickLength
    ) internal {

        ICircuitBreaker circuitBreaker = ICircuitBreaker(msg.sender);

        // If token does not have a rate limit, do nothing
        if (!isInitialized(identifier)) {
            return;
        }

        Limiter memory limiter = circuitBreaker.limiters(identifier);

        uint32 currentTickTimestamp = uint32(
            block.timestamp - (block.timestamp % tickLength)
        );
        limiter.liqInPeriod += amount;

        uint32 listHead = limiter.listHead;
        if (listHead == 0) {
            // if there is no head, set the head to the new inflow
            limiter.listHead = currentTickTimestamp;
            limiter.listTail = currentTickTimestamp;
            circuitBreaker.updateLiquidityChange(
                identifier,
                amount,
                currentTickTimestamp
            );
        } else {
            // if there is a head, check if the new inflow is within the period
            // if it is, add it to the head
            // if it is not, add it to the tail
            if (block.timestamp - listHead >= withdrawalPeriod) {
                sync(identifier, withdrawalPeriod);
            }

            // check if tail is the same as block.timestamp (multiple txs in same block)
            uint32 listTail = limiter.listTail;
            if (listTail == currentTickTimestamp) {
                // add amount
                circuitBreaker.updateLiquidityChange(
                    identifier,
                   circuitBreaker.listNodes(identifier, listTail).amount + amount,
                    currentTickTimestamp
                );
            } else {
                // add to tail
                circuitBreaker.updateLiquidityChange(
                    identifier,
                    amount,
                    currentTickTimestamp
                );
                limiter.listTail = currentTickTimestamp;
            }
        }

        circuitBreaker.updateSecurityParameter(
            identifier,
            limiter.minLiqRetainedBps,
            limiter.limitBeginThreshold,
            address(limiter.settlementModule)
        );
    }

    function sync(bytes32 identifier, uint256 withdrawalPeriod) internal {
        sync(identifier, withdrawalPeriod, type(uint256).max);
    }

    function sync(
        bytes32 identifier,
        uint256 withdrawalPeriod,
        uint256 totalIters
    ) internal {
        ICircuitBreaker circuitBreaker = ICircuitBreaker(msg.sender);
        Limiter memory limiter = circuitBreaker.limiters(identifier);
        uint32 currentHead = limiter.listHead;
        int256 totalChange = 0;
        uint256 iter = 0;

        while (
            currentHead != 0 &&
            block.timestamp - currentHead >= withdrawalPeriod &&
            iter < totalIters
        ) {
            LiqChangeNode memory node = circuitBreaker.listNodes(identifier, currentHead);
            totalChange += node.amount;
            currentHead = node.nextTimestamp;
            // Clear data
            delete node.amount;
            delete node.nextTimestamp;
            // forgefmt: disable-next-item
            unchecked {
                ++iter;
            }
        }

        if (currentHead == 0) {
            // If the list is empty, set the tail and head to current times
            limiter.listHead = uint32(block.timestamp);
            limiter.listTail = uint32(block.timestamp);
        } else {
            limiter.listHead = currentHead;
        }
        limiter.liqTotal += totalChange;
        limiter.liqInPeriod -= totalChange;
    }

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

        return
            (currentLiq + limiter.liqInPeriod) < //futureLiq
                // NOTE: uint256 to int256 conversion here is safe
                (currentLiq * int256(limiter.minLiqRetainedBps)) /
                    int256(BPS_DENOMINATOR) //minLiq
                ? LimitStatus.Triggered
                : LimitStatus.Ok;
    }

    function isInitialized(
        bytes32 identifier
    ) internal view returns (bool) {
        return ICircuitBreaker(msg.sender).limiters(identifier).minLiqRetainedBps > 0;
    }
     function isInitialized(
        Limiter storage limiter
    ) internal view returns (bool) {
        return limiter.minLiqRetainedBps > 0;
    }
}
