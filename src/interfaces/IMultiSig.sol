// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IMultiSig {
    function execute() external returns (bool);
    function getApprovalCount() external view returns (uint64);
    function requiredApprovals() external view returns(uint256);
}
