// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.19;

import {Limiter} from "../static/Structs.sol";

/// @title Circuit Breaker
/// @dev See https://eips.ethereum.org/EIPS/eip-7265
interface IERC7265CircuitBreaker {
    /**
     * @notice Event emitted whenever the security parameter is increased
     * @param amount The amount by which the security parameter is increased
     * @param identifier The identifier of the security parameter
     */
    event ParameterInrease(uint256 indexed amount, bytes32 indexed identifier);
    /**
     * @notice Event emitted whenever the security parameter is decreased
     * @param amount The amount by which the security parameter is decreased
     * @param identifier The identifier of the security parameter
     */
    event ParameterDecrease(uint256 indexed amount, bytes32 indexed identifier);
    /**
     * @notice Event emitted whenever an interaction is rate limited
     * @param identifier The identifier of the security parameter that triggered the rate limiting
     */
    event RateLimited(bytes32 indexed identifier);

    /**
     * @notice Function for increasing the current security parameter
     * @dev This function MAY only be called by the owner of the security parameter
     * // bytes32 identifier
     * // revertOnRateLimit
     * The function MUST emit the {ParameterSet} event
     */
    function increaseParameter(
        bytes32 identifier,
        uint256 amount,
        address settlementTarget,
        uint256 settlementValue,
        bytes memory settlementPayload
    ) external returns (bool);

    /**
     * @notice Function for decreasing the current security parameter
     * @dev This function MAY only be called by the owner of the security parameter
     * // bytes32 identifier
     * // revertOnRateLimit
     * The function MUST emit the {ParameterSet} event
     */
    function decreaseParameter(
        bytes32 identifier,
        uint256 amount,
        address settlementTarget,
        uint256 settlementValue,
        bytes memory settlementPayload
    ) external returns (bool);

    /**
     * @dev MAY be called by admin to configure a security parameter
     */
    function addSecurityParameter(
        bytes32 identifier,
        uint256 minLiqRetainedBps,
        uint256 limitBeginThreshold,
        address settlementModule
    ) external;

    /**
     * @dev MAY be called by admin to update configuration of a security parameter
     */
    function updateSecurityParameter(
        bytes32 identifier,
        uint256 minLiqRetainedBps,
        uint256 limitBeginThreshold,
        address settlementModule
    ) external;

    function isRateLimited(bytes32 identifier) external view returns (bool);

    /**
     * @dev MAY be called by admin to add protected contracts
     */
    function addProtectedContracts(address[] calldata _protectedContracts) external;

    /**
     * @dev MAY be called by admin to add protected contracts
     */
    function removeProtectedContracts(address[] calldata _protectedContracts) external;

    /// @notice Function for pausing / unpausing the Circuit Breaker
    /// @dev MAY be called by admin to pause / unpause the Circuit Breaker
    /// While the protocol is not operational: inflows, outflows, and claiming locked funds MUST revert
    function setCircuitBreakerOperationalStatus(bool newOperationalStatus) external;
}
