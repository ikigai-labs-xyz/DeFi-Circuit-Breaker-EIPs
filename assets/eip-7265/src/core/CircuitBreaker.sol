// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

import {IERC7265CircuitBreaker} from "../interfaces/IERC7265CircuitBreaker.sol";
import {ISettlementModule} from "../interfaces/ISettlementModule.sol";

import {Limiter, LiqChangeNode} from "../static/Structs.sol";
import {LimiterLib, LimitStatus} from "../utils/LimiterLib.sol";

contract CircuitBreaker is IERC7265CircuitBreaker, Ownable {
    using SafeERC20 for IERC20;
    using LimiterLib for Limiter;

    ////////////////////////////////////////////////////////////////
    //                      STATE VARIABLES                       //
    ////////////////////////////////////////////////////////////////

    mapping(bytes32 identifier => Limiter limiter) public limiters;
    mapping(address _contract => bool protectionActive)
        public isProtectedContract;

    uint256 public immutable WITHDRAWAL_PERIOD;

    uint256 public immutable TICK_LENGTH;

    bool public isOperational = true;

    uint256 public rateLimitEndTimestamp;

    uint256 public rateLimitCooldownPeriod;

    uint256 public gracePeriodEndTimestamp;

    

    ////////////////////////////////////////////////////////////////
    //                           ERRORS                           //
    ////////////////////////////////////////////////////////////////

    error CircuitBreaker__NotAProtectedContract();
    error CircuitBreaker__NotOperational();
    error CircuitBreaker__NotRateLimited();
    error CircuitBreaker__InvalidGracePeriodEnd();

    ////////////////////////////////////////////////////////////////
    //                         MODIFIERS                          //
    ////////////////////////////////////////////////////////////////

    modifier onlyProtected() {
        if (!isProtectedContract[msg.sender]) {
            revert CircuitBreaker__NotAProtectedContract();
        }
        _;
    }

    /**
     * @notice When the isOperational flag is set to false, the protocol is considered locked and will
     * revert all future deposits, withdrawals, and claims to locked funds.
     * The admin should migrate the funds from the underlying protocol and what is remaining
     * in the CircuitBreaker contract to a multisig. This multisig should then be used to refund users pro-rata.
     * (Social Consensus)
     */
    modifier onlyOperational() {
        if (!isOperational) revert CircuitBreaker__NotOperational();
        _;
    }

    /**
     * @notice CircuitBreaker constructor
     * @param _rateLimitCooldownPeriod The cooldown period for the rate limiter
     * @param _withdrawalPeriod The withdrawal period for the rate limiter
     * @param _liquidityTickLength The tick length for the rate limiter
     * @param _initialOwner The initial owner of the contract
     */
    constructor(
        uint256 _rateLimitCooldownPeriod,
        uint256 _withdrawalPeriod,
        uint256 _liquidityTickLength,
        address _initialOwner
    ) Ownable(_initialOwner) {
        rateLimitCooldownPeriod = _rateLimitCooldownPeriod;
        WITHDRAWAL_PERIOD = _withdrawalPeriod;
        TICK_LENGTH = _liquidityTickLength;
    }

    /// @dev OWNER FUNCTIONS

    /// @inheritdoc IERC7265CircuitBreaker
    function addProtectedContracts(
        address[] calldata _ProtectedContracts
    ) external override onlyOwner {
        for (uint256 i = 0; i < _ProtectedContracts.length; ++i) {
            isProtectedContract[_ProtectedContracts[i]] = true;
        }
    }

    /// @inheritdoc IERC7265CircuitBreaker
    function removeProtectedContracts(
        address[] calldata _ProtectedContracts
    ) external override onlyOwner {
        for (uint256 i = 0; i < _ProtectedContracts.length; ++i) {
            isProtectedContract[_ProtectedContracts[i]] = false;
        }
    }

    /// @dev CORE CIRCUIT BREAKER FUNCTIONS

    /// @inheritdoc IERC7265CircuitBreaker
    function addSecurityParameter(
        bytes32 identifier,
        uint256 minLiqRetainedBps,
        uint256 limitBeginThreshold,
        address settlementModule
    ) external override onlyOwner {
        _addSecurityParameter(
            identifier,
            minLiqRetainedBps,
            limitBeginThreshold,
            settlementModule
        );
    }

    /// @inheritdoc IERC7265CircuitBreaker
    function updateSecurityParameter(
        bytes32 identifier,
        uint256 minLiqRetainedBps,
        uint256 limitBeginThreshold,
        address settlementModule
    ) external override onlyOwner {
        _updateSecurityParameter(
            identifier,
            minLiqRetainedBps,
            limitBeginThreshold,
            settlementModule
        );
    }

    /// @inheritdoc IERC7265CircuitBreaker
    function setCircuitBreakerOperationalStatus(
        bool newOperationalStatus
    ) external override onlyOwner {
        isOperational = newOperationalStatus;
    }

    /**
     * @notice Called by the owner to set the rate limit cooldown period
     * @param _gracePeriodEndTimestamp The new rate limit cooldown period
     */
    function startGracePeriod(uint256 _gracePeriodEndTimestamp) external onlyOwner {
        if (_gracePeriodEndTimestamp <= block.timestamp) revert CircuitBreaker__InvalidGracePeriodEnd();
        gracePeriodEndTimestamp = _gracePeriodEndTimestamp;
        emit GracePeriodStarted(_gracePeriodEndTimestamp);
    }

    /**
     * @notice Called by the owner to override and disable rate limit
     * @param identifier The identifier of the limiter
     */
    function overrideRateLimit(bytes32 identifier) external onlyOwner {
        if (!(isRateLimited())) revert CircuitBreaker__NotRateLimited();
        rateLimitEndTimestamp = block.timestamp - 1;
        limiters[identifier].sync(WITHDRAWAL_PERIOD);
    }

    /**
     * @dev Override the status of the limiter
     * @param identifier The identifier of the limiter
     * @param overrideStatus The status to override to
     * @return bool the new status of the limiter
     */
    function setLimiterOverriden(
        bytes32 identifier,
        bool overrideStatus
    ) external onlyOwner returns (bool) {
        return limiters[identifier].overriden = overrideStatus;
    }

    /// @inheritdoc IERC7265CircuitBreaker
    function increaseParameter(
        bytes32 identifier,
        uint256 amount,
        address settlementTarget,
        uint256 settlementValue,
        bytes memory settlementPayload
    ) external override returns (bool) {
        return
            _increaseParameter(
                identifier,
                amount,
                settlementTarget,
                settlementValue,
                settlementPayload
            );
    }

    /// @inheritdoc IERC7265CircuitBreaker
    function decreaseParameter(
        bytes32 identifier,
        uint256 amount,
        address settlementTarget,
        uint256 settlementValue,
        bytes memory settlementPayload
    ) external override returns (bool) {
        return
            _decreaseParameter(
                identifier,
                amount,
                settlementTarget,
                settlementValue,
                settlementPayload
            );
    }

    /**
     * @dev Due to potential inactivity, the linked list may grow to where
     * it is better to clear the backlog in advance to save gas for the users
     * this is a public function so that anyone can call it as it is not user sensitive
     */
    function clearBackLog(bytes32 identifier, uint256 _maxIterations) external {
        limiters[identifier].sync(WITHDRAWAL_PERIOD, _maxIterations);
    }

    /// @dev EXTERNAL VIEW FUNCTIONS

    /// @inheritdoc IERC7265CircuitBreaker
    function isParameterRateLimited(bytes32 identifier) external view returns (bool) {
        return limiters[identifier].status() == LimitStatus.Triggered;
    }

    /// @inheritdoc IERC7265CircuitBreaker
    function isInGracePeriod() public view returns (bool) {
        return block.timestamp <= gracePeriodEndTimestamp;
    }

    function isRateLimited() public view returns (bool) {
        return block.timestamp <= rateLimitEndTimestamp;
    }

    /**
     * @notice Get the next timestamp and amount of the limiter at a given tick
     * @param identifier The identifier of the limiter
     * @param _tickTimestamp The timestamp of the tick
     * @return nextTimestamp The next timestamp of the tick
     * @return amount The amount value on the limiter at the tick
     */
    function liquidityChanges(
        bytes32 identifier,
        uint256 _tickTimestamp
    ) external view returns (uint256 nextTimestamp, int256 amount) {
        LiqChangeNode storage node = limiters[identifier].listNodes[
            uint32(_tickTimestamp)  
        ];
        nextTimestamp = node.nextTimestamp;
        amount = node.amount;
    }

    /// @dev INTERNAL FUNCTIONS

    /**
     * @notice Add a new security parameter
     * @param identifier The identifier of the limiter
     * @param minValBps The minimum value of the limiter in basis points
     * @param limitBeginThreshold The threshold to begin the limiter
     * @param settlementModule The settlement module to use
     */
    function _addSecurityParameter(
        bytes32 identifier,
        uint256 minValBps,
        uint256 limitBeginThreshold,
        address settlementModule
    ) internal {
        Limiter storage limiter = limiters[identifier];
        limiter.init(
            minValBps,
            limitBeginThreshold,
            ISettlementModule(settlementModule)
        );
        emit SecurityParameterAdded(
            identifier,
            minValBps,
            limitBeginThreshold,
            settlementModule
        );
    }

    /**
     * @notice Update a security parameter
     * @param identifier The identifier of the limiter
     * @param minValBps The minimum value of the limiter in basis points
     * @param limitBeginThreshold The threshold to begin the limiter
     * @param settlementModule The settlement module to use
     */
    function _updateSecurityParameter(
        bytes32 identifier,
        uint256 minValBps,
        uint256 limitBeginThreshold,
        address settlementModule
    ) internal {
        Limiter storage limiter = limiters[identifier];
        limiter.updateParams(
            minValBps,
            limitBeginThreshold,
            ISettlementModule(settlementModule)
        );
        limiter.sync(WITHDRAWAL_PERIOD);
    }

    /**
     * @notice Increase parameter on a limiter
     * @param identifier The identifier of the limiter
     * @param amount The amount to increase by
     * @param settlementTarget The settlement target
     * @param settlementValue The settlement value
     * @param settlementPayload The settlement payload
     * @return bool if the rate limit is triggered
     */
    function _increaseParameter(
        bytes32 identifier,
        uint256 amount,
        address settlementTarget,
        uint256 settlementValue,
        bytes memory settlementPayload
    ) internal onlyProtected onlyOperational returns (bool) {
        /// @dev uint256 could overflow into negative
        Limiter storage limiter = limiters[identifier];

        emit ParameterInrease(amount, identifier);
        limiter.recordChange(int256(amount), WITHDRAWAL_PERIOD, TICK_LENGTH);
        if (limiter.status() == LimitStatus.Triggered && !isInGracePeriod()) {
            emit RateLimited(identifier);
            rateLimitEndTimestamp = block.timestamp + rateLimitCooldownPeriod;
            _onCircuitBreakerTrigger(
                limiter,
                settlementTarget,
                settlementValue,
                settlementPayload
            );
            return true;
        }
        return false;
    }

    /**
     * @notice Decrease parameter on a limiter
     * @param identifier The identifier of the limiter
     * @param amount The amount to decrease by
     * @param settlementTarget The settlement target
     * @param settlementValue The settlement value
     * @param settlementPayload The settlement payload
     * @return bool if the rate limit is triggered
     */
    function _decreaseParameter(
        bytes32 identifier,
        uint256 amount,
        address settlementTarget,
        uint256 settlementValue,
        bytes memory settlementPayload
    ) internal onlyProtected onlyOperational returns (bool) {
        Limiter storage limiter = limiters[identifier];
        // Check if the token has enforced rate limited
        if (!limiter.isInitialized()) {
            // if it is not rate limited, just return false
            return false;
        }

        emit ParameterDecrease(amount, identifier);
        limiter.recordChange(-int256(amount), WITHDRAWAL_PERIOD, TICK_LENGTH);

        // Check if rate limit is triggered after withdrawal
        if (limiter.status() == LimitStatus.Triggered && !isInGracePeriod()) {
            emit RateLimited(identifier);
            rateLimitEndTimestamp = block.timestamp + rateLimitCooldownPeriod;
            _onCircuitBreakerTrigger(
                limiter,
                settlementTarget,
                settlementValue,
                settlementPayload
            );
            return true;
        }
        return false;
    }

    /**
     * @notice Called when the circuit breaker is triggered
     * @param limiter The limiter that was triggered
     * @param settlementTarget The settlement target
     * @param settlementValue The settlement value
     * @param settlementPayload The settlement payload
     */
    function _onCircuitBreakerTrigger(
        Limiter storage limiter,
        address settlementTarget,
        uint256 settlementValue,
        bytes memory settlementPayload
    ) internal virtual {
        limiter.settlementModule.prevent{value: settlementValue}(
            settlementTarget,
            settlementValue,
            settlementPayload
        );
    }
}
