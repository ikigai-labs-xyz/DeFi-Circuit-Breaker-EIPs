// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "../interfaces/IDelayedSettlementModule.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

/**
 * @title DelayedSettlementModule: a timelock to schedule transactions
 * @dev This contract combines the IDelayedSettlementModule interface with the TimelockController implementation.
 */
contract DelayedSettlementModule is
    IDelayedSettlementModule,
    TimelockController
{
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}

    function prevent(
        address target,
        uint256 value,
        bytes calldata innerPayload
    ) external payable override returns (bytes32 newEffectID) {
        newEffectID = keccak256(abi.encode(target, value, innerPayload));
        super.schedule(
            target,
            value,
            innerPayload,
            bytes32(0),
            bytes32(0),
            getMinDelay()
        );
        return newEffectID;
    }

    function execute(bytes calldata extendedPayload) external override {
        (address target, uint256 value, bytes memory innerPayload) = abi.decode(
            extendedPayload,
            (address, uint256, bytes)
        );
        super.execute(target, value, innerPayload, bytes32(0), bytes32(0));
    }

    function pausedTill()
        external
        view
        override
        returns (uint256 pauseTimestamp)
    {
        // TODO: Implement the pausing mechanism
        return 0;
    }
}
