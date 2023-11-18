// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Limiter} from "../static/Structs.sol";

/// @title Circuit Breaker
/// @dev See https://eips.ethereum.org/EIPS/eip-7265
interface IERC7265CircuitBreaker {
    /**
     * @notice Event emitted whenever a new security parameter configuration is added
     * @param identifier The identifier of the security parameter
     * @param minValBps The minimum value of the security parameter in percent
     * @param limitBeginThreshold The minimal amount of a security parameter that MUST be reached before the Circuit Breaker checks for a breach
     * @param settlementModule The address of the settlement module
     * @dev This event MUST be emitted when a new security parameter is added     
     */
    event SecurityParameterAdded(bytes32 indexed identifier, uint256 minValBps, uint256 limitBeginThreshold, address settlementModule);
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

    /// @dev MUST be emitted in `startGracePeriod` when a new grace period is successfully started
    /// @param gracePeriodEnd MUST be the end timestamp of the new grace period
    event GracePeriodStarted(uint256 gracePeriodEnd);

    /**
     * @notice Function for increasing the current security parameter
     * @param identifier is the identifier of the security parameter
     * Every security parameter has a unique bytes32 identifier. This allows for configuring multiple security parameters, for
     * multiple metrics within a single protocol (e.g. a protocol with multiple assets, or a protocol with multiple markets)
     * @param amount is the amount by which the security parameter is increased
     * @param settlementTarget is the target address for a potential settlement at the settlement module
     * This address gets called by the settlement module in case of the CircuitBreaker being triggered
     * @param settlementValue is the value for a potential settlement at the settlement module
     * This value gets sent to the settlement target by the settlement module in case of the CircuitBreaker being triggered
     * @param settlementPayload is the payload for a potential settlement at the settlement module
     * This payload gets sent to the settlement target by the settlement module in case of the CircuitBreaker being triggered
     * @dev This function MAY only be called by the owner of the security parameter
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
     * @param identifier is the identifier of the security parameter
     * Every security parameter has a unique bytes32 identifier. This allows for configuring multiple security parameters, for
     * multiple metrics within a single protocol (e.g. a protocol with multiple assets, or a protocol with multiple markets)
     * @param amount is the amount by which the security parameter is increased
     * @param settlementTarget is the target address for a potential settlement at the settlement module
     * This address gets called by the settlement module in case of the CircuitBreaker being triggered
     * @param settlementValue is the value for a potential settlement at the settlement module
     * This value gets sent to the settlement target by the settlement module in case of the CircuitBreaker being triggered
     * @param settlementPayload is the payload for a potential settlement at the settlement module
     * This payload gets sent to the settlement target by the settlement module in case of the CircuitBreaker being triggered
     * @dev This function MAY only be called by the owner of the security parameter
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
     * @notice Function for adding a security parameter
     * @param identifier is the identifier of the security parameter
     * Every security parameter has a unique bytes32 identifier. This allows for configuring multiple security parameters, for
     * multiple metrics within a single protocol (e.g. a protocol with multiple assets, or a protocol with multiple markets)
     * @param minValBps is the minimum amount a security parameter can reach in percent before the Circuit Breaker is triggered
     * @param limitBeginThreshold is the minimal amount of a security parameter that MUST be reached before the Circuit Breaker checks for a breach
     * This limits potential false positives triggered either by minor assets with low liquidity or by low liquidity during early stages of protocol launch.
     * Below this amount, withdrawals of this asset MUST NOT trigger a rate limit.
     * However, if a rate limit is triggered, assets below the minimum trigger amount to limit MUST still be locked.
     * @param settlementModule is the address of the settlement module
     * @dev MAY be called by admin to configure a security parameter
     */
    function addSecurityParameter(
        bytes32 identifier,
        uint256 minValBps,
        uint256 limitBeginThreshold,
        address settlementModule
    ) external;

    /**
     * @notice Function for updating the configuraiton for a security parameter
     * @param identifier is the identifier of the security parameter
     * Every security parameter has a unique bytes32 identifier. This allows for configuring multiple security parameters, for
     * multiple metrics within a single protocol (e.g. a protocol with multiple assets, or a protocol with multiple markets)
     * @param minValBps is the minimum amount a security parameter can reach in percent before the Circuit Breaker is triggered
     * @param limitBeginThreshold is the minimal amount of a security parameter that MUST be reached before the Circuit Breaker checks for a breach
     * This limits potential false positives triggered either by minor assets with low liquidity or by low liquidity during early stages of protocol launch.
     * Below this amount, withdrawals of this asset MUST NOT trigger a rate limit.
     * However, if a rate limit is triggered, assets below the minimum trigger amount to limit MUST still be locked.
        * @param settlementModule is the address of the settlement module
     * @dev MAY be called by admin to update configuration of a security parameter
     */
    function updateSecurityParameter(
        bytes32 identifier,
        uint256 minValBps,
        uint256 limitBeginThreshold,
        address settlementModule
    ) external;

    /**
     * @notice Function for returning if a security parameter is breached
     * @param identifier is the identifier of the security parameter
     * @dev MUST return true if the security parameter is breached
     */
    function isParameterRateLimited(bytes32 identifier) external view returns (bool);

    /**
     * @notice Add new protected contracts
     * @param _protectedContracts an array of addresses of protected contracts to add
     * @dev MUST be used to add protected contracts. Protected contracts MUST be part of your protocol. 
     * Protected contracts have the authority to trigger rate limits and withdraw assets. 
     * MUST revert if caller is not the current admin.
     * MUST store protected contracts in the stored state of the circuit breaker implementation.
     */ 
    function addProtectedContracts(address[] calldata _protectedContracts) external;

    /**
     * @notice Remove protected contracts
     * @param _protectedContracts an array of addresses of protected contracts to remove
     * @dev MAY be used to remove protected contracts. Protected contracts MUST be part of your protocol.
     * Protected contracts have the authority to trigger rate limits and withdraw assets.
     * MUST revert if caller is not the current admin.
     * MUST remove protected contracts from stored state in the circuit breaker implementation.
     */
    function removeProtectedContracts(address[] calldata _protectedContracts) external;

    /// @notice Function for pausing / unpausing the Circuit Breaker
    /// @param newOperationalStatus is the new operational status of the Circuit Breaker (true = operational, false = not operational)
    /// @dev MUST revert if caller is not the current admin.
    /// @dev MAY be called by admin to pause / unpause the Circuit Breaker
    /// While the protocol is not operational: inflows, outflows, and claiming locked funds MUST revert
    function setCircuitBreakerOperationalStatus(bool newOperationalStatus) external;

    /// @notice Override a rate limit
    /// @dev This method MAY be called when the protocol admin (typically governance) is certain that a rate limit is the result of a false positive.
    /// MUST revert if caller is not the current admin.
    /// MUST allow the grace period to extend for the full withdrawal period to not trigger the rate limit again if the rate limit is removed just before the withdrawal period ends.
    /// MUST revert if the circuit breaker is not currently rate limited.
    function overrideRateLimit(bytes32 identifier) external;

    /// @notice Check if the circuit breaker is currently in grace period
    /// @return isInGracePeriod MUST return TRUE if the circuit breaker is currently in grace period, FALSE otherwise
    function isInGracePeriod() external view returns (bool);
}
