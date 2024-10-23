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

    address[] public owners;
    address owner1 = address(1);
    address owner2 = address(2);
    address owner3 = address(3);

    address user = makeAddr('user');
    address zeroAddress = address(0);
    uint64 requiredApprovals;

    function setUp() public {
        DeployTreasuryDAO deployer = new DeployTreasuryDAO();
        (treasuryDAO, multiSig, config) = deployer.run();
        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);
        requiredApprovals = 2; // Minimum approvals needed
    }

    function testConstructorZeroOwners() public {
        address[] memory emptyOwners = new address[](0);
        vm.expectRevert(MultiSig.ZeroOwners.selector);
        new MultiSig(emptyOwners, requiredApprovals, address(treasuryDAO));
    }

    function testConstructorMaxOwnersExceeded() public {
        address[] memory manyOwners = new address[](11); // 11 owners
        for (uint160 i = 0; i < 11; i++) {
            manyOwners[i] = address(i + 1);
        }
        vm.expectRevert(MultiSig.MaximumNumberOfOwnersExceeded.selector);
        new MultiSig(manyOwners, requiredApprovals, address(treasuryDAO));
    }

    function testConstructorInvalidRequiredApprovals() public {
        vm.expectRevert(MultiSig.InvalidRequiredApprovals.selector);
        new MultiSig(owners, 0, address(treasuryDAO)); // Zero approvals
    }

    function testConstructorRequiredApprovalsExceedsOwners() public {
        vm.expectRevert(MultiSig.InvalidRequiredApprovals.selector);
        new MultiSig(owners, 4, address(treasuryDAO)); // More approvals than owners
    }

    function testConstructorZeroAddress() public {
        vm.expectRevert(MultiSig.ZeroAddress.selector);
        new MultiSig(owners, requiredApprovals, zeroAddress); // Zero TreasuryDAO address
    }

    function testConstructorDuplicateOwners() public {
        owners.push(owner1); // Duplicate owner
        vm.expectRevert(MultiSig.DuplicateOwner.selector);
        new MultiSig(owners, requiredApprovals, address(treasuryDAO));
    }

    function testApproveNotAnOwner() public {
        vm.expectRevert(MultiSig.NotAnOwner.selector);
        vm.prank(address(4)); // Not an owner
        multiSig.approve();
    }

    function testApproveAlreadyApproved() public {
        vm.prank(owner1);
        multiSig.approve(); // First approval should succeed

        vm.prank(owner1);
        vm.expectRevert(MultiSig.AlreadyApproved.selector); // Second approval should fail
        multiSig.approve();
    }

    function testExecuteNotAllowedToCall() public {
        vm.prank(owner1);
        multiSig.approve(); // Approve first owner
        vm.prank(owner2);
        multiSig.approve(); // Approve second owner

        vm.expectRevert(MultiSig.NotAllowedToCall.selector);
        vm.prank(address(5)); // Not address(treasuryDAO)
        multiSig.execute();
    }

    function testExecuteRequiredApprovalsNotMet() public {
        vm.prank(owner1);
        multiSig.approve(); // Approve only one owner

        vm.expectRevert(MultiSig.RequiredApprovalsNotMet.selector);
        vm.prank(address(treasuryDAO));
        multiSig.execute(); // Not enough approvals
    }

    function testExecuteSuccess() public {
        // Approve required number of owners
        vm.prank(owner1);
        multiSig.approve();
        vm.prank(owner2);
        multiSig.approve();

        vm.prank(address(treasuryDAO));
        bool success = multiSig.execute(); // Should succeed
        assertTrue(success);
    }
}