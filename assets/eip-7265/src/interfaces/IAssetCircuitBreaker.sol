// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {IERC7265CircuitBreaker} from "./IERC7265CircuitBreaker.sol";

/// @title IAssetCircuitBreaker
/// @dev This interface defines the methods for the AssetCircuitBreaker
interface IAssetCircuitBreaker is IERC7265CircuitBreaker {
    /// @dev MUST be emitted in `onTokenInflow` and `onNativeAssetInflow` when an asset is successfully deposited
    /// @param asset MUST be the address of the asset withdrawn.
    /// For any EIP-20 token, MUST be an EIP-20 token contract.
    /// For the native asset (ETH on mainnet), MUST be address 0x0000000000000000000000000000000000000001 equivalent to address(1).
    /// @param from MUST be the address from which the assets originated
    /// @param amount MUST be the amount of assets being withdrawn
    event AssetDeposit(
        address indexed asset,
        address indexed from,
        uint256 amount
    );

    /// @dev MUST be emitted in `onTokenOutflow` and `onNativeAssetOutflow` when an asset is successfully withdrawn
    /// @param asset MUST be the address of the asset withdrawn.
    /// For any EIP-20 token, MUST be an EIP-20 token contract.
    /// For the native asset (ETH on mainnet), MUST be address 0x0000000000000000000000000000000000000001 equivalent to address(1).
    /// @param recipient MUST be the address of the recipient withdrawing the assets
    /// @param amount MUST be the amount of assets being withdrawn
    event AssetWithdraw(
        address indexed asset,
        address indexed recipient,
        uint256 amount
    );

    /// @dev MUST be emitted in `registerAsset` when an asset is registered
    /// @param asset MUST be the address of the asset for which to set rate limit parameters.
    /// For any EIP-20 token, MUST be an EIP-20 token contract.
    /// For the native asset (ETH on mainnet), MUST be address 0x0000000000000000000000000000000000000001 equivalent to address(1).
    /// @param metricThreshold The threshold metric which defines when a rate limit is triggered
    /// @param minAmountToLimit The minimum amount of nominal asset liquidity at which point rate limits can be triggered
    event AssetRegistered(
        address indexed asset,
        uint256 metricThreshold,
        uint256 minAmountToLimit
    );

    /// @notice Record EIP-20 token inflow into a protected contract
    /// @dev This method MUST be called from all protected contract methods where an EIP-20 token is transferred in from a user.
    /// MUST revert if caller is not a protected contract.
    /// MUST revert if circuit breaker is not operational.
    /// @param _token MUST be an EIP-20 token contract
    /// @param _amount MUST equal the amount of token transferred into the protected contract
    function onTokenInflow(address _token, uint256 _amount) external;

    /// @notice Record EIP-20 token outflow from a protected contract and transfer tokens to recipient if rate limit is not triggered
    /// @dev This method MUST be called from all protected contract methods where an EIP-20 token is transferred out to a user.
    /// Before calling this method, the protected contract MUST transfer the EIP-20 tokens to the circuit breaker contract.
    /// For an example, see ProtectedContract.sol in the reference implementation.
    /// MUST revert if caller is not a protected contract.
    /// MUST revert if circuit breaker is not operational.
    /// If the token is not registered, this method MUST NOT revert and MUST transfer the tokens to the recipient.
    /// @param _token MUST be an EIP-20 token contract
    /// @param _amount MUST equal the amount of tokens transferred out of the protected contract
    /// @param _recipient MUST be the address of the recipient of the transferred tokens from the protected contract
    function onTokenOutflow(
        address _token,
        uint256 _amount,
        address _recipient
    ) external;

    /// @notice Record native asset (ETH on mainnet) inflow into a protected contract
    /// @dev This method MUST be called from all protected contract methods where native asset is transferred in from a user.
    /// MUST revert if caller is not a protected contract.
    /// MUST revert if circuit breaker is not operational.
    /// @param _amount MUST equal the amount of native asset transferred into the protected contract
    function onNativeAssetInflow(uint256 _amount) external;

    /// @notice Record native asset (ETH on mainnet) outflow from a protected contract and transfer native asset to recipient if rate limit is not triggered
    /// @dev This method MUST be called from all protected contract methods where native asset is transferred out to a user.
    /// When calling this method, the protected contract MUST send the native asset to the circuit breaker contract in the same call.
    /// For an example, see ProtectedContract.sol in the reference implementation.
    /// MUST revert if caller is not a protected contract.
    /// MUST revert if circuit breaker is not operational.
    /// If native asset is not registered, this method MUST NOT revert and MUST transfer the native asset to the recipient.
    /// If a rate limit is not triggered or the circuit breaker is in grace period, this method MUST NOT revert and MUST transfer the native asset to the recipient.
    /// If a rate limit is triggered and the circuit breaker is not in grace period and `_revertOnRateLimit` is TRUE, this method MUST revert.
    /// If a rate limit is triggered and the circuit breaker is not in grace period and `_revertOnRateLimit` is FALSE and caller is a protected contract, this method MUST NOT revert.
    /// If a rate limit is triggered and the circuit breaker is not in grace period, this method MUST record the locked funds in the internal accounting of the circuit breaker implementation.
    /// @param _recipient MUST be the address of the recipient of the transferred native asset from the protected contract
    function onNativeAssetOutflow(address _recipient) external payable;

    /// @notice Register rate limit parameters for a given asset
    /// @dev Each asset that will be rate limited MUST be registered using this function, including the native asset (ETH on mainnet).
    /// If an asset is not registered, it will not be subject to rate limiting or circuit breaking and unlimited immediate withdrawals MUST be allowed.
    /// MUST revert if the caller is not the current admin.
    /// MUST revert if the asset has already been registered.
    /// @param _asset The address of the asset for which to set rate limit parameters.
    /// To set the rate limit parameters for any EIP-20 token, MUST be an EIP-20 token contract.
    /// To set rate limit parameters For the native asset, MUST be address 0x0000000000000000000000000000000000000001 equivalent to address(1).
    /// @param _minLiqRetainedBps The threshold metric which defines when a rate limit is triggered.
    /// This is intentionally left open to allow for various implementations, including percentage-based (see reference implementation), nominal, and more.
    /// MUST be greater than 0.
    /// @param _limitBeginThreshold The minimum amount of nominal asset liquidity at which point rate limits can be triggered.
    /// This limits potential false positives triggered either by minor assets with low liquidity or by low liquidity during early stages of protocol launch.
    /// Below this amount, withdrawals of this asset MUST NOT trigger a rate limit.
    /// However, if a rate limit is triggered, assets below the minimum trigger amount to limit MUST still be locked.
    /// @param _settlementModule The address of the settlement module for this asset.
    function registerAsset(
        address _asset,
        uint256 _minLiqRetainedBps,
        uint256 _limitBeginThreshold,
        address _settlementModule
    ) external;

    /// @notice Modify rate limit parameters for a given asset
    /// @dev MAY be used only after registering an asset.
    /// MUST revert if asset is not previously registered with the `registerAsset` method.
    /// MUST revert if the caller is not the current admin.
    /// @param _asset The address of the asset contract for which to set rate limit parameters.
    /// To update the rate limit parameters for any EIP-20 token, MUST be an EIP-20 token contract.
    /// To update the rate limit parameters For the native asset (ETH on mainnet), MUST be address 0x0000000000000000000000000000000000000001 equivalent to address(1).
    /// @param _minLiqRetainedBps The threshold metric which defines when a rate limit is triggered.
    /// This is left open to allow for various implementations, including percentage-based (see reference implementation), nominal, and more.
    /// MUST be greater than 0.
    /// @param _limitBeginThreshold The minimum amount of nominal asset liquidity at which point rate limits can be triggered.
    /// This limits potential false positives caused both by minor assets with low liquidity and by low liquidity during early stages of protocol launch.
    /// Below this amount, withdrawals of this asset MUST NOT trigger a rate limit.
    /// However, if a rate limit is triggered, assets below the minimum amount to limit MUST still be locked.
    /// @param _settlementModule The address of the settlement module for this asset.
    function updateAssetParams(
        address _asset,
        uint256 _minLiqRetainedBps,
        uint256 _limitBeginThreshold,
        address _settlementModule
    ) external;

    /**
     * @notice Function for checking if an asset is rate limited by the CircuitBreaker
     * @param token is the address of the asset to check
     * @dev MUST return true if the asset is rate limited by the CircuitBreaker
     */
    function isTokenRateLimited(address token) external view returns (bool);
}
