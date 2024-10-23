//SPDX-License-Identifier: MIT
pragma solidity ^ 0.8.18;

import {Script} from "forge-std/Script.sol";
import {TreasuryDAO} from "../src/TreasuryDAO.sol";
import {MultiSig} from "../src/MultiSig.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployTreasuryDAO is Script {
    uint256[] public chainIds = [
        421614,
        84532,
        168587773,
        11155111,
        4202,
        919,
        11155420,
        80002
    ];
    address[] public owners = [
        address(1),
        address(2),
        address(3)
    ];
    uint256 public maxAllowed = 1000e6;

    function run() external returns (TreasuryDAO, MultiSig, HelperConfig){
        HelperConfig config = new HelperConfig();
        (address permit2, address spokePool, uint256 deployerKey) = config.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        TreasuryDAO treasuryDAO = new TreasuryDAO(
            permit2,
            spokePool,
            chainIds,
            maxAllowed
        );
        MultiSig multiSig = new MultiSig(
            owners,
            2,
            address(treasuryDAO)
        );

        treasuryDAO.transferOwnership(address(1));
        vm.stopBroadcast();
        return(treasuryDAO, multiSig, config);
    }
}