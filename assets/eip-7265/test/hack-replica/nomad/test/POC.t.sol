// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../../../src/settlement/RejectSettlementModule.sol";
import "../../../../src/core/CircuitBreaker.sol";
import "../src/Replica/packages/contracts-core/contracts/Replica.sol";
import "../src/Replica/packages/contracts-bridge/contracts/BridgeRouter.sol";

import "./utils/Attacker.sol";
import "./utils/Constants.sol";

// Foundry cheatsheet: https://github.com/foundry-rs/foundry/blob/master/forge/README.md#cheat-codes
// Foundry doc: https://book.getfoundry.sh

contract ReplicaPOC is Test, Constants {
   Replica replica = Replica(0xB92336759618F55bd0F8313bd843604592E27bd8);
   BridgeRouter bridgeRouter = BridgeRouter(payable(Constants.BRIDGE_ROUTER));
   Attacker attacker;
   address ADMIN = makeAddr("ADMIN");

   RejectSettlementModule rejectSettlementModule;
   CircuitBreaker circuitBreaker;

   uint256 PRE_HACK_BLOCK = 15_259_100; // block before first hack

   function setUp() public {
      vm.createSelectFork('https://rpc.ankr.com/eth', PRE_HACK_BLOCK);

      attacker = new Attacker();

      // circuit breaker setup
      rejectSettlementModule = new RejectSettlementModule();
      circuitBreaker = new CircuitBreaker(
         0, // _rateLimitCooldownPeriod,
         60 * 60, // _withdrawalPeriod, time window in blocks
         12, // _liquidityTickLength,
         ADMIN // _initialOwner
      );

      address [] memory protectedContracts = new address [] (1);
      protectedContracts[0] = Constants.ERC20_BRIDGE;

      vm.prank(ADMIN);
      circuitBreaker.addProtectedContracts(protectedContracts);

      registerAsset(Constants.WBTC);
      registerAsset(Constants.WETH);
      registerAsset(Constants.USDC);
      registerAsset(Constants.USDT);
      registerAsset(Constants.DAI);
      registerAsset(Constants.FRAX);
      registerAsset(Constants.CQT);

      // overriding bytecode
      BridgeRouter circuitBreakerRouter = new BridgeRouter();
      circuitBreakerRouter.setCircuitBreaker(address(circuitBreaker));
      console.log("set");
      vm.etch(Constants.BRIDGE_ROUTER_IMPL, address(circuitBreakerRouter).code);

      BridgeRouter(payable(Constants.ERC20_BRIDGE)).setCircuitBreaker(address(circuitBreaker));
      // bridgeRouter.setCircuitBreaker(address(circuitBreaker));
   }

   function registerAsset(address asset) internal {
      vm.prank(ADMIN);
      circuitBreaker.addSecurityParameter(
         keccak256(abi.encodePacked(asset)), // _asset,
         900, // _minLiqRetainedBps, - % of minimal value that the security param should always hold in escrow
         0, // _limitBeginThreshold,
         address(rejectSettlementModule) // _settlementModule
      );
   }

   function addressToAssetId(address _addr) internal pure returns (bytes32) {
      return keccak256(abi.encodePacked(_addr));
   }

   function testReplicaPOCSetup() public {
      assert(address(replica) == 0xB92336759618F55bd0F8313bd843604592E27bd8);
      assertEq(block.number, PRE_HACK_BLOCK);
   }

   function testExploit() public {
      attacker.attack();
   }
}
