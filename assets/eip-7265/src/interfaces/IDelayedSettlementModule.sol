// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/**
 * @title Interface for the Delayed Settlement Module (DSM): a timelock to schedule transactions
 * @dev This interface defines the functions for :
 * - scheduling delayed settlement
 * - executing  delayed settlement
 * - get paused status
 */
interface IDelayedSettlementModule {
    /**
     * @notice Schedules a delayed call from the DSM to a target.
     * @dev The call includes the calldata innerPayload and callvalue of value.
     * The function should return a unique identifier for the scheduled effect as newEffectID.
     * @param target The address of the target contract.
     * @param value The amount of native token to be sent with the call.
     * @param innerPayload The calldata for the call.
     * @return newEffectID A unique identifier for the scheduled effect.
     */
    function schedule(
        address target,
        uint256 value,
        bytes calldata innerPayload
    ) external payable returns (bytes32 newEffectID);

    /**
     * @notice Executes a settled effect based on the decoded contents in the extendedPayload.
     * @dev The extendedPayload should have the format <version 1-byte> | <inner data N-bytes>.
     * @param extendedPayload The payload for the call.
     *
     * TODO: provide docs for the extendedPayload payload format
     */
    function execute(bytes calldata extendedPayload) external;

    /**
     * @notice Returns the UNIX timestamp at which the last module pause occurred.
     * @dev The function may return 0 if the contract has not been paused yet.
     * It should return a value that's at least 2**248 if the contract is currently paused until further notice.
     * It should return 2**256 - 1.
     * @return pauseTimestamp The UNIX timestamp of the last pause.
     *
     * TODO: provide docs for the pausing mechanism
     */
    function pausedTill() external view returns (uint256 pauseTimestamp);
}
