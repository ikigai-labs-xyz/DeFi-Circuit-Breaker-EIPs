// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";
import {MockToken} from "../../mocks/MockToken.sol";
import {AssetCircuitBreaker} from "../../../src/core/AssetCircuitBreaker.sol";
import {DelayedSettlementModule} from "../../../src/settlement/DelayedSettlementModule.sol";
import {LimiterLib} from "../../../src/utils/LimiterLib.sol";

contract AssetCircuitBreakerTest is Test {
    MockToken internal token;
    MockToken internal secondToken;
    MockToken internal unlimitedToken;

    address internal NATIVE_ADDRESS_PROXY = address(1);
    AssetCircuitBreaker internal circuitBreaker;
    DelayedSettlementModule internal delayedSettlementModule;

    address internal alice = vm.addr(0x1);
    address internal bob = vm.addr(0x2);
    address internal admin = vm.addr(0x3);

    /**
     * @dev Emitted when a call is scheduled as part of operation `id`.
     */
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );

    function setUp() public {
        token = new MockToken("USDC", "USDC");
        circuitBreaker = new AssetCircuitBreaker(3 days, 4 hours, 5 minutes, admin);
        delayedSettlementModule = new DelayedSettlementModule(
            1 seconds,
            new address[](0),
            new address[](0),
            admin
        );

        // allow token circuit breaker to propose (for calling prevent function)
        vm.prank(admin);
        delayedSettlementModule.grantRole(
            keccak256("PROPOSER_ROLE"),
            address(circuitBreaker)
        );

        vm.prank(admin);
        // Protect USDC with 70% max drawdown per 4 hours
        circuitBreaker.registerAsset(
            address(token),
            7000,
            1000e18,
            address(delayedSettlementModule)
        );
        vm.prank(admin);
        circuitBreaker.registerAsset(
            NATIVE_ADDRESS_PROXY,
            7000,
            1000e18,
            address(delayedSettlementModule)
        );
        vm.warp(1 hours);

        // register this contract
        address[] memory protectedContracts = new address[](1);
        protectedContracts[0] = address(this);
        vm.prank(admin);
        circuitBreaker.addProtectedContracts(protectedContracts);
    }

    function test_getTokenIdentifier() public {
        assertEq(
            circuitBreaker.getTokenIdentifier(address(token)),
            keccak256(abi.encodePacked(address(token)))
        );
        assertEq(
            circuitBreaker.getTokenIdentifier(NATIVE_ADDRESS_PROXY),
            keccak256(abi.encodePacked(NATIVE_ADDRESS_PROXY))
        );
    }

    function test_onTokenOutflow_createsCorrectCalldata() public {
        // cause firewall trigger (withdraw more than 30%)
        // 1 Million USDC deposited
        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.transfer(address(circuitBreaker), 1_000_000e18);
        circuitBreaker.onTokenInflow(address(token), 1_000_000e18);

        uint256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);

        bytes memory expectedCalldata = abi.encodeWithSelector(
            bytes4(keccak256("transfer(address,uint256)")),
            address(token),
            withdrawalAmount
        );

        // bytes32 expectedId =
        //     delayedSettlementModule.hashOperation(address(token), 0, expectedCalldata, bytes32(0), bytes32(0));

        // TODO: figure out why expected id is different from actual one

        // vm.expectEmit(true, true, true, true, address(delayedSettlementModule));

        // emit CallScheduled(
        //     expectedId, 0, address(token), 0, expectedCalldata, bytes32(0), delayedSettlementModule.getMinDelay()
        // );

        // circuitBreaker.onTokenOutflow(address(token), withdrawalAmount, alice);
    }

    function test_onTokenOutflow_doesNotTransferFundsIfTrigger() public {
        // cause firewall trigger (withdraw more than 30%)
        // 1 Million USDC deposited
        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.transfer(address(circuitBreaker), 1_000_000e18);
        circuitBreaker.onTokenInflow(address(token), 1_000_000e18);

        uint256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);

        circuitBreaker.onTokenOutflow(address(token), withdrawalAmount, alice);

        // balance of alice should not have increased
        assertEq(token.balanceOf(alice), 0);
    }

    function test_onNativeOutflow_doesNotTransferFundsIfTrigger() public {
        // cause firewall trigger (withdraw more than 30%)

        // 10 thousand USDC deposited
        circuitBreaker.onNativeAssetInflow(10_000e18);

        uint256 withdrawalAmount = 3_001e18;
        vm.warp(5 hours);

        vm.deal(address(this), 3_001e18);
        circuitBreaker.onNativeAssetOutflow{value: withdrawalAmount}(alice);

        // balance of alice should not have increased
        assertEq(token.balanceOf(alice), 0);
    }

    function test_onFirewallTrigger_decodesTokenAmountSuccessfully() public {
        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.transfer(address(circuitBreaker), 1_000_000e18);
        circuitBreaker.onTokenInflow(address(token), 1_000_000e18);

        uint256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);

        circuitBreaker.onTokenOutflow(address(token), withdrawalAmount, alice);

        // test if tokens transferred to DSM
        assertEq(
            token.balanceOf(address(delayedSettlementModule)),
            withdrawalAmount
        );
    }

    function test_onTokenOutflow_WhenOverriden_transferFundsIfTrigger() public {
        // cause firewall trigger (withdraw more than 30%)
        // 1 Million USDC deposited
        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.transfer(address(circuitBreaker), 1_000_000e18);
        circuitBreaker.onTokenInflow(address(token), 1_000_000e18);
        bytes32 tokenIdentifier = circuitBreaker.getTokenIdentifier(
            address(token)
        );
        vm.prank(admin);
        circuitBreaker.setLimiterOverriden(tokenIdentifier, true);

        uint256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);

        circuitBreaker.onTokenOutflow(address(token), withdrawalAmount, alice);

        // balance of alice should not have increased
        assertEq(token.balanceOf(alice), 300_001e18);
    }
}
