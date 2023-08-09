// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./ISettlementModule.sol";

/**
 * @title Interface for the Reject Settlement Module: reject transactions when the firewall triggers
 * @dev This interface defines the functions for :
 * - preventing settlement via rejecting
 * - executing settlement
 */
interface IRejectSettlementModule is ISettlementModule {
    /**
     * @notice Preventing a transaction for a RejectSettlement Module reverts the transaction
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
     * @notice In the context of the RejectSettlement Module, the transaction has already been reverted and cannot be executed.
     * @dev The extendedPayload should have the format <version 1-byte> | <inner data N-bytes>.
     * @param extendedPayload The payload for the call.
     *
     * TODO: provide docs for the extendedPayload payload format
     */
    function execute(bytes calldata extendedPayload) external;
}
