// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test,console} from "forge-std/Test.sol";
import {TreasuryDAO} from "../src/TreasuryDAO.sol";
import {MultiSig} from "../src/MultiSig.sol";
import {DeployTreasuryDAO} from "../script/DeployTreasuryDAO.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract TreasuryDAOTest is Test {
    TreasuryDAO treasuryDAO;
    MultiSig multiSig;
    HelperConfig config = new HelperConfig();
    address owner = address(1);
    address user = makeAddr('user');
    address zeroAddress = address(0);

    function setUp() public {
        DeployTreasuryDAO deployer = new DeployTreasuryDAO();
        (treasuryDAO, multiSig, config) = deployer.run();
    }

    function calculateRelayerFee(uint256 amount) private pure returns(uint64){
        return uint64((amount * 40) / 100);
    }

    function testScheduleValidIntentForETH() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 1 ether,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1 ether)
        });

        vm.prank(user);
        vm.deal(user, intent.amount + intent.relayerFee);
        treasuryDAO.scheduleOrModifyIntent{value: intent.amount + intent.relayerFee}(intent);
        (,uint256 amount,,,,) = treasuryDAO.intents(user);
        
        assertEq(amount, 1 ether);
        assertEq(treasuryDAO.users(1), user);
    }

    function testScheduleValidIntentForToken() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: address(6),
            amount: 1000e6,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1000e6)
        });

        vm.prank(user);
        vm.deal(user, intent.amount + intent.relayerFee);
        treasuryDAO.scheduleOrModifyIntent{value: intent.amount + intent.relayerFee}(intent);
        
        (,uint256 amount,,,,) = treasuryDAO.intents(user);
        
        assertEq(amount, 1000e6);
        assertEq(treasuryDAO.users(1), user);
    }

    function testScheduleInvalidIntentZeroToken() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: zeroAddress,
            amount: 1 ether,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1 ether)
        });

        vm.prank(user);
        vm.expectRevert(TreasuryDAO.InvalidIntent.selector);
        treasuryDAO.scheduleOrModifyIntent(intent);
    }

    function testScheduleInvalidIntentZeroAmount() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 0,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(0)
        });

        vm.prank(user);
        vm.expectRevert(TreasuryDAO.InvalidIntent.selector);
        treasuryDAO.scheduleOrModifyIntent(intent);
    }

    function testInvalidIntentZeroRecipient() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 1 ether,
            recipient: zeroAddress,
            destinationChainId: 1155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1 ether)
        });

        vm.prank(user);
        vm.expectRevert(TreasuryDAO.InvalidIntent.selector);
        treasuryDAO.scheduleOrModifyIntent(intent);
    }

    function testScheduleInvalidIntentPastExecutionTime() public {
        vm.warp(block.timestamp + 2 days);
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 1 ether,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp - 1 days,
            relayerFee: calculateRelayerFee(1 ether)
        });

        vm.prank(user);
        vm.expectRevert(TreasuryDAO.InvalidIntent.selector);
        treasuryDAO.scheduleOrModifyIntent(intent);
    }

    function testInvalidIntentHighRelayerFee() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 1 ether,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1 ether) + calculateRelayerFee(1 ether) // 100% of the amount
        });

        vm.prank(user);
        vm.expectRevert(TreasuryDAO.InvalidIntent.selector);
        treasuryDAO.scheduleOrModifyIntent(intent);
    }

    function testInvalidIntentUnsupportedChainId() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 1 ether,
            recipient: zeroAddress,
            destinationChainId: 1,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1 ether)
        });

        vm.prank(user);
        vm.expectRevert(TreasuryDAO.InvalidIntent.selector);
        treasuryDAO.scheduleOrModifyIntent(intent);
    }

    function testInvalidZeroChainID() public {
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 0; // Invalid chain ID
        (address permit2, address spokePool, ) = config.activeNetworkConfig();
        vm.expectRevert(TreasuryDAO.InvalidZeroChainID.selector);
        new TreasuryDAO(permit2, spokePool, chainIds, 1000e6);
    }

    function testNotEnoughNative() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 1 ether,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1 ether)
        });

        vm.prank(user);
        vm.deal(user, intent.relayerFee);
        vm.expectRevert(abi.encodeWithSelector(TreasuryDAO.NotEnoughNative.selector, intent.relayerFee));
        treasuryDAO.scheduleOrModifyIntent{value: intent.relayerFee}(intent); // Not enough ETH sent
    }

    function testSetMultiSig() public {
        vm.prank(owner);
        treasuryDAO.setMultiSig(address(multiSig));
        assertEq(address(treasuryDAO.multiSig()), address(multiSig));
    }

    function testSetMultiSigZeroAddress() public {
        vm.expectRevert(TreasuryDAO.ZeroAddress.selector);
        vm.prank(owner);
        treasuryDAO.setMultiSig(zeroAddress);
    }
}
