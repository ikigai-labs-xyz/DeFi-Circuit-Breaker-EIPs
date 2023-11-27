// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ISettlementModule} from "../interfaces/ISettlementModule.sol";
import {Limiter, LiqChangeNode} from "../static/Structs.sol";
import {LimitStatus} from "../utils/LimiterLib.sol";

interface ICircuitBreaker {
    ////////////////////////////////////////////////////////////////
    //                      STATE VARIABLES                       //
    ////////////////////////////////////////////////////////////////

    function limiters(
        bytes32 identifier
    ) external view returns (Limiter memory);

    function listNodes(
        bytes32 identifier,
        uint32 tick
    ) external view returns (LiqChangeNode memory);

    function isProtectedContract(
        address _contract
    ) external view returns (bool);

    function WITHDRAWAL_PERIOD() external view returns (uint256);

    function TICK_LENGTH() external view returns (uint256);

    function isOperational() external view returns (bool);

    function rateLimitEndTimestamp() external view returns (uint256);

    function rateLimitCooldownPeriod() external view returns (uint256);

    function gracePeriodEndTimestamp() external view returns (uint256);

    ////////////////////////////////////////////////////////////////
    //                         FUNCTIONS                          //
    ////////////////////////////////////////////////////////////////

    function addProtectedContracts(
        address[] calldata _ProtectedContracts
    ) external;

    function removeProtectedContracts(
        address[] calldata _ProtectedContracts
    ) external;

    function addSecurityParameter(
        bytes32 identifier,
        uint256 minLiqRetainedBps,
        uint256 limitBeginThreshold,
        address settlementModule
    ) external;

    function updateSecurityParameter(
        bytes32 identifier,
        uint256 minLiqRetainedBps,
        uint256 limitBeginThreshold,
        address settlementModule
    ) external;

    function setCircuitBreakerOperationalStatus(
        bool newOperationalStatus
    ) external;

    function startGracePeriod(uint256 _gracePeriodEndTimestamp) external;

    function overrideRateLimit(bytes32 identifier) external;

    function setLimiterOverriden(
        bytes32 identifier,
        bool overrideStatus
    ) external returns (bool);

    function increaseParameter(
        bytes32 identifier,
        uint256 amount,
        address settlementTarget,
        uint256 settlementValue,
        bytes memory settlementPayload
    ) external returns (bool);

    function decreaseParameter(
        bytes32 identifier,
        uint256 amount,
        address settlementTarget,
        uint256 settlementValue,
        bytes memory settlementPayload
    ) external returns (bool);

    function updateLiquidityChange(
        bytes32 identifier,
        int256 amount,
        uint32 tickTimestamp
    ) external;

    function clearBackLog(bytes32 identifier, uint256 _maxIterations) external;

    function isParameterRateLimited(
        bytes32 identifier
    ) external view returns (bool);

    function isInGracePeriod() external view returns (bool);

    function isRateLimited() external view returns (bool);

    function liquidityChanges(
        bytes32 identifier,
        uint32 _tickTimestamp
    ) external view returns (uint256 nextTimestamp, int256 amount);
}
