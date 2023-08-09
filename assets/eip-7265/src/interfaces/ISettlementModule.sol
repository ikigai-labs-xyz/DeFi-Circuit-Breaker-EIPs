// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/**
 * @title Interface for Settlement Modules: timelock (freeze funds) , Reject, etc
 * @dev This interface defines the functions for :
 * - preventing transactions when the firewall is triggered
 * - executing a transaction previously prevented
 * - get paused status
 */
interface ISettlementModule {
    /**
     * @notice Schedules a delayed call from the DSM to a target.
     * @dev The call includes the calldata innerPayload and callvalue of value.
     * The function should return a unique identifier for the scheduled effect as newEffectID.
     * @param target The address of the target contract.
     * @param value The amount of native token to be sent with the call.
     * @param innerPayload The calldata for the call.
     * @return newEffectID A unique identifier for the scheduled effect.
     */
    function prevent(
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
}
