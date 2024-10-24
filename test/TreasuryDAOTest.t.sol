// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console, StdUtils} from "forge-std/Test.sol";
import {TreasuryDAO} from "../src/TreasuryDAO.sol";
import {MultiSig} from "../src/MultiSig.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployTreasuryDAO} from "../script/DeployTreasuryDAO.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract TreasuryDAOTest is Test {
    TreasuryDAO treasuryDAO;
    MultiSig multiSig;
    HelperConfig config = new HelperConfig();
    address owner = address(1);
    address user = makeAddr("user");
    address zeroAddress = address(0);

    function setUp() public {
        DeployTreasuryDAO deployer = new DeployTreasuryDAO();
        (treasuryDAO, multiSig, config) = deployer.run();
    }

    function calculateRelayerFee(uint256 amount) private pure returns (uint64) {
        return uint64((amount * 40) / 100);
    }

    function scheduleETHTransfer(address _user) public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 500e8,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(500e8),
            executed: false
        });

        vm.prank(_user);
        vm.deal(user, intent.amount + intent.relayerFee);
        treasuryDAO.scheduleOrModifyIntent{
            value: intent.amount + intent.relayerFee
        }(intent);
        vm.stopPrank();
    }

    function testScheduleValidIntentForETH() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 1 ether,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1 ether),
            executed: false
        });

        vm.prank(user);
        vm.deal(user, intent.amount + intent.relayerFee);
        treasuryDAO.scheduleOrModifyIntent{
            value: intent.amount + intent.relayerFee
        }(intent);
        (, uint256 amount, , , , , ) = treasuryDAO.intents(user);

        assertEq(amount, 1 ether);
        assertEq(treasuryDAO.users(0), user);
    }

    function testScheduleValidIntentForToken() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: address(6),
            amount: 1000e6,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1000e6),
            executed: false
        });

        vm.prank(user);
        vm.deal(user, intent.amount + intent.relayerFee);
        treasuryDAO.scheduleOrModifyIntent{
            value: intent.amount + intent.relayerFee
        }(intent);

        (, uint256 amount, , , , , ) = treasuryDAO.intents(user);

        assertEq(amount, 1000e6);
        assertEq(treasuryDAO.users(0), user);
    }

    function testScheduleInvalidIntentZeroToken() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: zeroAddress,
            amount: 1 ether,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1 ether),
            executed: false
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
            relayerFee: calculateRelayerFee(0),
            executed: false
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
            relayerFee: calculateRelayerFee(1 ether),
            executed: false
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
            relayerFee: calculateRelayerFee(1 ether),
            executed: false
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
            relayerFee: calculateRelayerFee(1 ether),
            executed: false
        });

        vm.prank(user);
        vm.expectRevert(TreasuryDAO.InvalidIntent.selector);
        treasuryDAO.scheduleOrModifyIntent(intent);
    }

    function testInvalidZeroChainID() public {
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 0; // Invalid chain ID
        (address permit2, address spokePool, address wethAddress, ) = config
            .activeNetworkConfig();
        vm.expectRevert(TreasuryDAO.InvalidZeroChainID.selector);
        new TreasuryDAO(
            permit2,
            spokePool,
            wethAddress,
            chainIds,
            1000e6,
            0.5 ether
        );
    }

    function testNotEnoughNative() public {
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 1 ether,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 1 days,
            relayerFee: calculateRelayerFee(1 ether),
            executed: false
        });

        vm.prank(user);
        vm.deal(user, intent.relayerFee);
        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryDAO.NotEnoughNative.selector,
                intent.relayerFee
            )
        );
        treasuryDAO.scheduleOrModifyIntent{value: intent.relayerFee}(intent); // Not enough ETH sent
    }

    function testSetMultiSig() public {
        vm.prank(owner);
        treasuryDAO.setMultiSig(address(multiSig));
        assertEq(address(treasuryDAO.getMultiSig()), address(multiSig));
    }

    function testSetMultiSigZeroAddress() public {
        vm.expectRevert(TreasuryDAO.ZeroAddress.selector);
        vm.prank(owner);
        treasuryDAO.setMultiSig(zeroAddress);
    }

    // function testPermit2() public {
    //     IAllowanceTransfer.PermitDetails memory permitDetails = IAllowanceTransfer.PermitDetails(
    //         0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
    //         1000e8,
    //         uint48(block.timestamp + 5 minutes),
    //         1
    //     );
    //     IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle(
    //         permitDetails,
    //         address(treasuryDAO),
    //         block.timestamp + 10 minutes
    //     );

    //     vm.prank(user);
    //     vm.deal(user, 1 ether);
    //     deal(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14, user, 1000e8);
    //     treasuryDAO.permitAndTransferToMe(
    //         permitSingle,"",1000e8
    //     );

    // }

    function testAcrossTransfer() public {
        scheduleETHTransfer(address(11));
        scheduleETHTransfer(address(12));
        scheduleETHTransfer(address(13));
        uint256[] memory intents = new uint256[](2);
        intents[0] = 0;
        intents[1] = 2;
        vm.prank(address(12));
        vm.warp(block.timestamp + 2 days);
        treasuryDAO.triggerIntent(intents);
    }

    function testCheckUpkeep() public {
        scheduleETHTransfer(address(11));
        scheduleETHTransfer(address(12));
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 500e8,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 3 days,
            relayerFee: calculateRelayerFee(500e8),
            executed: false
        });
        vm.prank(address(14));
        vm.deal(user, intent.amount + intent.relayerFee);
        treasuryDAO.scheduleOrModifyIntent{
            value: intent.amount + intent.relayerFee
        }(intent);
        vm.stopPrank();
        scheduleETHTransfer(address(13));

        uint256[] memory intents = new uint256[](3);
        intents[0] = 0;
        intents[1] = 1;
        intents[2] = 3;
        vm.warp(block.timestamp + 2 days);
        (bool performUpkeep, bytes memory data) = treasuryDAO.checkUpkeep("");
        assertEq(performUpkeep, true);
        assertEq(intents, abi.decode(data, (uint256[])));
    }

    function testPerformUpkeep() public {
        scheduleETHTransfer(address(11));
        scheduleETHTransfer(address(12));
        TreasuryDAO.Intent memory intent = TreasuryDAO.Intent({
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount: 500e8,
            recipient: user,
            destinationChainId: 11155420,
            executeAt: block.timestamp + 3 days,
            relayerFee: calculateRelayerFee(500e8),
            executed: false
        });
        vm.deal(address(14), intent.amount + intent.relayerFee);
        vm.prank(address(14));
        treasuryDAO.scheduleOrModifyIntent{
            value: intent.amount + intent.relayerFee
        }(intent);
        vm.stopPrank();
        scheduleETHTransfer(address(13));

        vm.warp(block.timestamp + 2 days);
        (, bytes memory data) = treasuryDAO.checkUpkeep("");
        treasuryDAO.performUpkeep(data);
    }
}
