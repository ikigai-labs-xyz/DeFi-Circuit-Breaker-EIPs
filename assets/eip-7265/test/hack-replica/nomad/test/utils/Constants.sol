// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 
contract Constants {
   address public constant REPLICA = 0x5D94309E5a0090b165FA4181519701637B6DAEBA;
   address public constant BRIDGE_ROUTER = 0xD3dfD3eDe74E0DCEBC1AA685e151332857efCe2d;
   address public constant BRIDGE_ROUTER_IMPL = 0x15fdA9F60310d09FEA54E3c99d1197DfF5107248;
   address public constant ERC20_BRIDGE = 0x88A69B4E698A4B090DF6CF5Bd7B2D47325Ad30A3;
   //address public constant ERC20_BRIDGE_IMPL = 0xe0db61ac718f502B485DEc66D013afbbE0B52F84;
  
   // Nomad domain IDs
   uint32 public constant ETHEREUM = 0x657468;   // "eth"
   uint32 public constant MOONBEAM = 0x6265616d; // "beam"
 
   address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
   address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
   address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
   address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
   address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
   address public constant FRAX = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
   address public constant CQT = 0xD417144312DbF50465b1C641d016962017Ef6240;
}
