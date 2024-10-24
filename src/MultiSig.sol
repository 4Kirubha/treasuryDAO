// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

contract MultiSig {
    error ZeroOwners();
    error MaximumNumberOfOwnersExceeded();
    error InvalidRequiredApprovals();
    error ZeroAddress();
    error DuplicateOwner();
    error NotAnOwner();
    error AlreadyApproved();
    error RequiredApprovalsNotMet();
    error NotAllowedToCall();

    address[] private owners; // Owners array
    uint8 private constant maxOwners = 10; // Maximum number of owners approval required
    mapping(address => bool) public isOwner; // To check the address is owner
    uint64 public requiredApprovals; // Required number of approvals to execute

    mapping(address owner => bool approved) private approved; // Check which owners were approved
    address private treasuryDAO;

    constructor(
        address[] memory _owners,
        uint64 _requiredApprovals,
        address _treasuryDAO
    ) {
        uint256 _noOfOwners = _owners.length;
        // Check whether the number of owners is not a zero
        if (_noOfOwners <= 0) revert ZeroOwners();
        // Check whether the owners reached maximum limit
        if (_noOfOwners > maxOwners) revert MaximumNumberOfOwnersExceeded();
        // Check whether the required approvals are lessthan or equal to the number of owners
        if (_requiredApprovals == 0 || _requiredApprovals > _noOfOwners)
            revert InvalidRequiredApprovals();

        if (_treasuryDAO == address(0)) revert ZeroAddress();
        for (uint64 i; i < _noOfOwners; i++) {
            address _owner = _owners[i];
            // Check the owner address is non zero
            if (_owner == address(0)) revert ZeroAddress();
            // Check, the same owner address is not repeated
            if (isOwner[_owner]) revert DuplicateOwner();

            isOwner[_owner] = true;
            owners.push(_owner);
        }

        requiredApprovals = _requiredApprovals;
        treasuryDAO = _treasuryDAO;
    }

    /**
     * @dev modifier to check whether the caller is owner or not
     */
    modifier onlyOwners() {
        if (!isOwner[msg.sender]) revert NotAnOwner();
        _;
    }

    modifier onlyTreasuryDAO() {
        if (msg.sender != treasuryDAO) revert NotAllowedToCall();
        _;
    }

    /**
     * @dev Function to approve
     */
    function approve() external onlyOwners {
        // Check, the caller(owner) has already approved
        if (approved[msg.sender]) revert AlreadyApproved();
        // Change the mapping to true
        approved[msg.sender] = true;
    }

    /**
     * @dev Gets the pause approval
     */
    function getApprovalCount() public view returns (uint64) {
        uint64 count;
        uint256 noOfOwners = owners.length; // Total number of owners
        for (uint256 i = 0; i < noOfOwners; i++) {
            // Check the owner has approved
            if (approved[owners[i]]) {
                count += 1;
            }
        }
        return count;
    }

    // /**
    //  * @dev Execute, If reqired approvals from the owners met
    //  */
    // function execute() external onlyTreasuryDAO returns (bool) {
    //     Get the number of approvals
    //     if (getApprovalCount() < requiredApprovals) revert RequiredApprovalsNotMet();
    //     uint256 noOfOwners = owners.length;
    //     for (uint256 i = 0; i < noOfOwners; i++) {
    //         approved[owners[i]] = false;
    //     }
    //     return true;
    // }
}
