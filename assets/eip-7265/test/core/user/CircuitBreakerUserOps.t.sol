// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {MockToken} from "../../mocks/MockToken.sol";
import {MockDeFiProtocol} from "../../mocks/MockDeFiProtocol.sol";
import {AssetCircuitBreaker} from "../../../src/core/AssetCircuitBreaker.sol";
import {DelayedSettlementModule} from "../../../src/settlement/DelayedSettlementModule.sol";
import {LimiterLib} from "../../../src/utils/LimiterLib.sol";

contract CircuitBreakerUserOpsTest is Test {
    MockToken internal token;
    MockToken internal secondToken;
    MockToken internal unlimitedToken;

    address internal NATIVE_ADDRESS_PROXY = address(1);
    AssetCircuitBreaker internal circuitBreaker;
    DelayedSettlementModule internal delayedSettlementModule;
    MockDeFiProtocol internal deFi;

    address internal alice = vm.addr(0x1);
    address internal bob = vm.addr(0x2);
    address internal admin = vm.addr(0x3);

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

        deFi = new MockDeFiProtocol(address(circuitBreaker));

        address[] memory addresses = new address[](1);
        addresses[0] = address(deFi);

        vm.prank(admin);
        circuitBreaker.addProtectedContracts(addresses);

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
    }

    function test_deposit_withDrawNoLimitTokenShouldBeSuccessful() public {
        unlimitedToken = new MockToken("DAI", "DAI");
        unlimitedToken.mint(alice, 10000e18);

        vm.prank(alice);
        unlimitedToken.approve(address(deFi), 10000e18);

        vm.prank(alice);
        deFi.deposit(address(unlimitedToken), 10000e18);

        assertEq(
            circuitBreaker.isTokenRateLimited(address(unlimitedToken)),
            false
        );
        vm.warp(1 hours);
        vm.prank(alice);
        deFi.withdrawal(address(unlimitedToken), 10000e18);
        assertEq(
            circuitBreaker.isTokenRateLimited(address(unlimitedToken)),
            false
        );
    }

    function test_deposit_shouldBeSuccessful() public {
        token.mint(alice, 10000e18);

        vm.prank(alice);
        token.approve(address(deFi), 10000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 10e18);

        assertEq(circuitBreaker.isTokenRateLimited(address(token)), false);

        bytes32 identifier = keccak256(abi.encodePacked(address(token)));
        (
            ,
            ,
            int256 liqTotal,
            int256 liqInPeriod,
            uint256 head,
            uint256 tail,
            ,

        ) = circuitBreaker.limiters(identifier);

        assertEq(head, tail);
        assertEq(liqTotal, 0);
        assertEq(liqInPeriod, 10e18);

        (uint256 nextTimestamp, int256 amount) = circuitBreaker
            .liquidityChanges(identifier, head);
        assertEq(nextTimestamp, 0);
        assertEq(amount, 10e18);

        vm.warp(1 hours);
        vm.prank(alice);
        deFi.deposit(address(token), 110e18);
        assertEq(circuitBreaker.isTokenRateLimited(address(token)), false);
        (, , liqTotal, liqInPeriod, , , , ) = circuitBreaker.limiters(
            identifier
        );
        assertEq(liqTotal, 0);
        assertEq(liqInPeriod, 120e18);

        // All the previous deposits are now out of the window and accounted for in the historacle
        vm.warp(10 hours);
        vm.prank(alice);
        deFi.deposit(address(token), 10e18);
        assertEq(circuitBreaker.isTokenRateLimited(address(token)), false);
        (, , liqTotal, liqInPeriod, head, tail, , ) = circuitBreaker.limiters(
            identifier
        );
        assertEq(liqTotal, 120e18);
        assertEq(liqInPeriod, 10e18);

        assertEq(head, block.timestamp);
        assertEq(tail, block.timestamp);
        assertEq(head % 5 minutes, 0);
        assertEq(tail % 5 minutes, 0);
    }

    function test_clearBacklog_shouldBeSuccessful() public {
        token.mint(alice, 10000e18);

        vm.prank(alice);
        token.approve(address(deFi), 10000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 1);

        vm.warp(2 hours);
        vm.prank(alice);
        deFi.deposit(address(token), 1);

        vm.warp(3 hours);
        vm.prank(alice);
        deFi.deposit(address(token), 1);

        vm.warp(4 hours);
        vm.prank(alice);
        deFi.deposit(address(token), 1);

        vm.warp(5 hours);
        vm.prank(alice);
        deFi.deposit(address(token), 1);

        vm.warp(6.5 hours);
        bytes32 identifier = keccak256(abi.encodePacked(address(token)));
        circuitBreaker.clearBackLog(identifier, 10);

        (
            ,
            ,
            int256 liqTotal,
            int256 liqInPeriod,
            uint256 head,
            uint256 tail,
            ,

        ) = circuitBreaker.limiters(identifier);
        // only deposits from 2.5 hours and later should be in the window
        assertEq(liqInPeriod, 3);
        assertEq(liqTotal, 2);

        assertEq(head, 3 hours);
        assertEq(tail, 5 hours);
    }

    function test_withdrawl_shouldBeSuccessful() public {
        token.mint(alice, 10000e18);

        vm.prank(alice);
        token.approve(address(deFi), 10000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 100e18);

        vm.warp(1 hours);
        vm.prank(alice);
        deFi.withdrawal(address(token), 60e18);
        assertEq(circuitBreaker.isTokenRateLimited(address(token)), false);
        bytes32 identifier = keccak256(abi.encodePacked(address(token)));
        (, , int256 liqTotal, int256 liqInPeriod, , , , ) = circuitBreaker
            .limiters(identifier);
        assertEq(liqInPeriod, 40e18);
        assertEq(liqTotal, 0);
        assertEq(token.balanceOf(alice), 9960e18);

        // All the previous deposits are now out of the window and accounted for in the historacle
        vm.warp(10 hours);
        vm.prank(alice);
        deFi.deposit(address(token), 10e18);
        assertEq(circuitBreaker.isTokenRateLimited(address(token)), false);

        uint256 tail;
        uint256 head;
        (, , liqTotal, liqInPeriod, head, tail, , ) = circuitBreaker.limiters(
            identifier
        );
        assertEq(liqInPeriod, 10e18);
        assertEq(liqTotal, 40e18);

        assertEq(head, block.timestamp);
        assertEq(tail, block.timestamp);
    }

    function test_tokenBreach() public {
        // 1 Million USDC deposited
        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.approve(address(deFi), 1_000_000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 1_000_000e18);

        // HACK
        // 300k USDC withdrawn
        int256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);
        vm.prank(alice);
        deFi.withdrawal(address(token), uint256(withdrawalAmount));
        assertEq(circuitBreaker.isTokenRateLimited(address(token)), true);
        bytes32 identifier = keccak256(abi.encodePacked(address(token)));
        (, , int256 liqTotal, int256 liqInPeriod, , , , ) = circuitBreaker
            .limiters(identifier);
        assertEq(liqInPeriod, -withdrawalAmount);
        assertEq(liqTotal, 1_000_000e18);

        assertEq(
            token.balanceOf(address(delayedSettlementModule)),
            uint256(withdrawalAmount)
        );
        assertEq(token.balanceOf(alice), 0);
        assertEq(
            token.balanceOf(address(deFi)),
            1_000_000e18 - uint256(withdrawalAmount)
        );

        // TODO: include testing proposal being submitted on DSM
        // test negation of proposal for releasing hacked funds

        // Attempts to withdraw more than the limit
        vm.warp(6 hours);
        vm.prank(alice);
        int256 secondAmount = 10_000e18;
        deFi.withdrawal(address(token), uint256(secondAmount));
        assertEq(circuitBreaker.isTokenRateLimited(address(token)), true);
        (, , liqTotal, liqInPeriod, , , , ) = circuitBreaker.limiters(
            identifier
        );
        assertEq(liqInPeriod, -withdrawalAmount - secondAmount);
        assertEq(liqTotal, 1_000_000e18);

        assertEq(
            token.balanceOf(address(delayedSettlementModule)),
            uint256(withdrawalAmount + secondAmount)
        );
        assertEq(token.balanceOf(alice), 0);

        // TODO: test executing release of funds on DSM
    }

    function test_nativeBreach() public {
        // 1 Million USDC deposited
        // give alice 1 million eth using vm
        vm.deal(alice, 10_000e18);

        // deposit 1000e18 to activate
        vm.prank(alice);
        deFi.depositNative{value: 10_000e18}();

        // withdraw more than 30% (cause firewall trigger)
        int256 withdrawalAmount = 3_001e18;
        vm.warp(5 hours);
        deFi.withdrawalNative(uint256(withdrawalAmount));
        assertEq(
            circuitBreaker.isTokenRateLimited(address(NATIVE_ADDRESS_PROXY)),
            true
        );
        bytes32 identifier = keccak256(
            abi.encodePacked(address(NATIVE_ADDRESS_PROXY))
        );
        (, , int256 liqTotal, int256 liqInPeriod, , , , ) = circuitBreaker
            .limiters(identifier);
        assertEq(liqInPeriod, -withdrawalAmount);
        assertEq(liqTotal, 10_000e18);

        assertEq(
            address(delayedSettlementModule).balance,
            uint256(withdrawalAmount)
        );
        assertEq(address(alice).balance, 0);

        // TODO: include testing proposal being submitted on DSM
        // test negation of proposal for releasing hacked funds

        // second withdrawal
        // Attempts to withdraw more than the limit
        vm.warp(6 hours);
        vm.prank(alice);
        int256 secondAmount = 1_000e18;
        deFi.withdrawalNative(uint256(secondAmount));
        assertEq(
            circuitBreaker.isTokenRateLimited(address(NATIVE_ADDRESS_PROXY)),
            true
        );
        (, , liqTotal, liqInPeriod, , , , ) = circuitBreaker.limiters(
            identifier
        );
        assertEq(liqInPeriod, -withdrawalAmount - secondAmount);
        assertEq(liqTotal, 10_000e18);

        // TODO: test executing release of funds on DSM
    }

    function test_breachAndLimitExpired() public {
        // 1 Million USDC deposited
        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.approve(address(deFi), 1_000_000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 1_000_000e18);

        // HACK
        // 300k USDC withdrawn
        int256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);
        vm.prank(alice);
        deFi.withdrawal(address(token), uint256(withdrawalAmount));
        assertEq(circuitBreaker.isTokenRateLimited(address(token)), true);
        assertEq(circuitBreaker.isRateLimited(), true);

        vm.warp(4 days);
        vm.prank(alice);
        assertEq(circuitBreaker.isRateLimited(), false);
    }

    function test_depositsAndWithdrawlsInSameTickLength() public {
        vm.warp(1 days);
        token.mint(alice, 10000e18);

        vm.prank(alice);
        token.approve(address(deFi), 10000e18);

        // 10 USDC deposited
        vm.prank(alice);
        deFi.deposit(address(token), 10e18);

        bytes32 identifier = keccak256(abi.encodePacked(address(token)));
        (, , , , uint256 head, , , ) = circuitBreaker.limiters(identifier);
        assertEq(head % 5 minutes, 0);

        // 1 minute later 10 usdc deposited, 1 usdc withdrawn all within the same tick length
        vm.warp(1 days + 1 minutes);
        vm.prank(alice);
        deFi.deposit(address(token), 10e18);

        deFi.withdrawal(address(token), 1e18);

        (uint256 nextTimestamp, int256 amount) = circuitBreaker
            .liquidityChanges(identifier, head);
        assertEq(nextTimestamp, 0);
        assertEq(amount, 19e18);

        // Next tick length, 1 usdc withdrawn
        vm.warp(1 days + 6 minutes);
        vm.prank(alice);
        deFi.withdrawal(address(token), 1e18);

        (nextTimestamp, amount) = circuitBreaker.liquidityChanges(
            identifier,
            head
        );
        assertEq(
            nextTimestamp,
            1 days + 6 minutes - ((1 days + 6 minutes) % 5 minutes)
        );
        assertEq(nextTimestamp % 5 minutes, 0);
        // previous tick length has 19 usdc deposited
        assertEq(amount, 19e18);

        // Next tick values
        (nextTimestamp, amount) = circuitBreaker.liquidityChanges(
            identifier,
            nextTimestamp
        );
        assertEq(nextTimestamp, 0);
        assertEq(amount, -1e18);
    }

    function testDepositsFuzzed(uint256 amount) public {
        // used to test compare gas costs of deposits
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(deFi), amount);
        vm.prank(alice);
        deFi.depositNoCircuitBreaker(address(token), amount);
    }

    function test_nativeDepositsFuzzed(uint256 amount) public {
        // used to test compare gas costs of deposits
        vm.deal(alice, amount);
        vm.prank(alice);
        deFi.depositNative{value: amount}();
    }

    function test_nativeWithdrawalsShouldBeSuccessful() public {
        vm.deal(alice, 10000e18);

        vm.prank(alice);
        deFi.depositNative{value: 100e18}();

        vm.warp(1 hours);
        vm.prank(alice);
        deFi.withdrawalNative(60e18);
        assertEq(
            circuitBreaker.isTokenRateLimited(NATIVE_ADDRESS_PROXY),
            false
        );
        bytes32 identifier = keccak256(abi.encodePacked(NATIVE_ADDRESS_PROXY));
        (, , int256 liqTotal, int256 liqInPeriod, , , , ) = circuitBreaker
            .limiters(identifier);
        assertEq(liqInPeriod, 40e18);
        assertEq(liqTotal, 0);
        assertEq(alice.balance, 9960e18);

        // All the previous deposits are now out of the window and accounted for in the historacle
        vm.warp(10 hours);
        vm.prank(alice);
        deFi.depositNative{value: 10e18}();
        assertEq(
            circuitBreaker.isTokenRateLimited(NATIVE_ADDRESS_PROXY),
            false
        );

        uint256 tail;
        uint256 head;
        (, , liqTotal, liqInPeriod, head, tail, , ) = circuitBreaker.limiters(
            identifier
        );
        assertEq(liqInPeriod, 10e18);
        assertEq(liqTotal, 40e18);

        assertEq(head, block.timestamp);
        assertEq(tail, block.timestamp);
    }
}
