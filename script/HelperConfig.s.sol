//SPDX-License-Identifier: MIT
pragma solidity ^ 0.8.18;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig{
        address permit2;
        address spokePool;
        uint256 deployerKey;
    }

    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;
    
    constructor(){
        if(block.chainid == 11155111){
            activeNetworkConfig = getSepoliaEthConfig();
        }else if(block.chainid == 11155420){
            activeNetworkConfig = getOPSepoliaEthConfig();
        }else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory){
        return NetworkConfig({
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,
            spokePool: 0x5ef6C01E11889d86803e0B23e3cB3F9E9d97B662,
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }

    function getOPSepoliaEthConfig() public pure returns (NetworkConfig memory){
        return NetworkConfig({
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,
            spokePool: 0x4e8E101924eDE233C13e2D8622DC8aED2872d505,
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }

    function getOrCreateAnvilEthConfig() public view returns (NetworkConfig memory){
        if (activeNetworkConfig.spokePool != address(0)) {
            return activeNetworkConfig;
        }
        return NetworkConfig({
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,
            spokePool: 0x4e8E101924eDE233C13e2D8622DC8aED2872d505,
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}