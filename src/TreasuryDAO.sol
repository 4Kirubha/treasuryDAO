// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

// Import necessary interfaces and libraries
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {SpokePoolInterface} from "./interfaces/ISpokePool.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IMultiSig} from "./interfaces/IMultiSig.sol";
import {console} from "forge-std/console.sol";

// Main contract for Treasury DAO
contract TreasuryDAO is Ownable {
    // Custom error definitions for better error handling
    error InvalidSpender();
    error InvalidIntent();
    error InvalidZeroChainID();
    error ZeroAddress();
    error NotEnoughNative(uint256 amount);
    error NotAllowedToTransfer(uint256 index);

    // Event emitted when an intent is scheduled
    event ScheduledIntent(address user, Intent intent);

    // Struct representing an intent
    struct Intent {
        address token;               // Token address for the transfer
        uint256 amount;              // Amount of tokens to transfer
        address recipient;           // Recipient address for the transfer
        uint256 destinationChainId;  // ID of the destination chain
        uint256 executeAt;           // Timestamp for when the transfer should occur
        uint64 relayerFee;           // Fee for the relayer
        bool executed;               // Status of intent execution
    }

    // Contract state variables
    IAllowanceTransfer private immutable permit2;            // Permit2 contract for allowances
    SpokePoolInterface private immutable spokePool;          // SpokePool contract for cross-chain transfers
    IMultiSig private multiSig;                               // Multi-sig contract for approvals
    uint256 private totalIntents;                             // Total number of scheduled intents
    uint256 private immutable maxTokenAllowedWithoutMultiSig; // Max tokens allowed for transfer without multi-sig
    uint256 private immutable maxETHAllowedWithoutMultiSig;   // Max ETH allowed for transfer without multi-sig
    address private constant nativeAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Native token address
    address private immutable wethAddress;                     // WETH address
    mapping(uint256 => address) public users;                // Mapping from intent number to user
    mapping(address => Intent) public intents;               // Mapping from user to their intent
    mapping(uint256 => bool) public supportedChains;         // Mapping for supported chains

    // Constructor to initialize the contract
    constructor(
        address _permit2,
        address _spokePool,
        address _wethAddress,
        uint256[] memory chainIds,
        uint256 _maxAllowedToken,
        uint256 _maxAllowedETH
    ) Ownable() {
        // Validate addresses
        if (_spokePool == address(0) || _permit2 == address(0)) {
            revert ZeroAddress();
        }

        // Initialize supported chains
        uint256 arrayLength = chainIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            if (chainIds[i] == 0) revert InvalidZeroChainID();
            supportedChains[chainIds[i]] = true;
        }

        // Assign contract addresses and limits
        permit2 = IAllowanceTransfer(_permit2);
        spokePool = SpokePoolInterface(_spokePool);
        wethAddress = _wethAddress;
        maxTokenAllowedWithoutMultiSig = _maxAllowedToken;
        maxETHAllowedWithoutMultiSig = _maxAllowedETH;
    }

    // Function to set multi-sig address
    function setMultiSig(address _multiSig) external onlyOwner {
        if (_multiSig == address(0)) revert ZeroAddress();
        multiSig = IMultiSig(_multiSig);
    }

    // Function to schedule or modify an intent
    function scheduleOrModifyIntent(Intent memory intent) external payable {
        // Validate the intent details
        if (
            intent.token == address(0) ||
            intent.amount == 0 ||
            intent.recipient == address(0) ||
            intent.executeAt <= block.timestamp ||
            intent.destinationChainId == block.chainid ||
            !supportedChains[intent.destinationChainId]
        ) revert InvalidIntent();

        // Check if enough native currency is provided
        if (intent.token == nativeAddress && msg.value < intent.amount) {
            revert NotEnoughNative(msg.value);
        }

        // If this is the first intent for the user, track them
        if (intents[msg.sender].amount == 0) {
            users[totalIntents] = msg.sender;
            totalIntents++;
        }
        intent.executed = false;
        intents[msg.sender] = intent;

        emit ScheduledIntent(msg.sender, intent);
    }

    // Function to permit and transfer tokens to the contract
    function permitAndTransferToContract(
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature,
        uint160 amount
    ) external {
        if (permitSingle.spender != address(this)) revert InvalidSpender();
        permit2.permit(msg.sender, permitSingle, signature);
        permit2.transferFrom(
            msg.sender,
            address(this),
            amount,
            permitSingle.details.token
        );
    }

    // Function to check if upkeep is needed
    function checkUpkeep(
        bytes calldata /*checkData*/
    ) external view returns (bool upkeepNeeded, bytes memory performData) {
        uint256 numberofValidIntents;
        for (uint256 i = 0; i < totalIntents; i++) {
            if (intents[users[i]].executeAt < block.timestamp) {
                ++numberofValidIntents;
            }
        }

        uint256[] memory validIntents = new uint256[](numberofValidIntents);
        uint256 index;
        for (uint256 i = 0; i < totalIntents; i++) {
            if (
                intents[users[i]].executeAt < block.timestamp &&
                !intents[users[i]].executed
            ) {
                validIntents[index] = i;
                ++index;
            }
        }
        if (validIntents.length > 0) {
            upkeepNeeded = true;
            performData = abi.encode(validIntents);
        }
    }

    // Function to trigger intents for execution
    function triggerIntent(uint256[] memory intentsToTrigger) external {
        bytes memory validIntends = abi.encode(intentsToTrigger);
        performUpkeep(validIntends);
    }

    // Function to perform the upkeep of valid intents
    function performUpkeep(bytes memory performData) public {
        uint256[] memory validIntents = abi.decode(performData, (uint256[]));
        if (validIntents[validIntents.length - 1] > (totalIntents - 1))
            revert InvalidIntent();
        for (uint256 i = 0; i < validIntents.length; i++) {
            Intent memory intent = intents[users[validIntents[i]]];
            if (
                intents[users[validIntents[i]]].executeAt < block.timestamp &&
                !intents[users[validIntents[i]]].executed
            ) {
                if (
                    intent.token == nativeAddress &&
                    intent.amount < maxETHAllowedWithoutMultiSig
                ) {
                    _crossChainTransfer(intent);
                    intents[users[validIntents[i]]].executed = true;
                } else if (
                    intent.token != nativeAddress &&
                    intent.amount < maxTokenAllowedWithoutMultiSig
                ) {
                    _crossChainTransfer(intent);
                    intents[users[validIntents[i]]].executed = true;
                } else {
                    if (
                        multiSig.getApprovalCount() >=
                        multiSig.requiredApprovals()
                    ) {
                        _crossChainTransfer(intent);
                        intents[users[validIntents[i]]].executed = true;
                    }
                }
            }
        }
    }

    // Internal function to perform the cross-chain transfer
    function _crossChainTransfer(Intent memory intent) internal {
        uint256 ethValue;
        if (intent.token == nativeAddress) {
            ethValue = intent.amount + intent.relayerFee;
            intent.token = wethAddress; // Convert native to WETH
        } else {
            ethValue = intent.relayerFee;
            IERC20(intent.token).approve(address(spokePool), intent.amount); // Approve token transfer
        }
        // Call deposit on spoke pool for cross-chain transfer
        spokePool.deposit{value: intent.amount}(
            intent.recipient,
            intent.token,
            intent.amount,
            intent.destinationChainId,
            int64(intent.relayerFee),
            uint32(block.timestamp),
            "",
            type(uint256).max
        );
    }

    // Getter functions for various contract addresses and limits
    function getSpokePool() external view returns (address) {
        return address(spokePool);
    }

    function getMultiSig() external view returns (address) {
        return address(multiSig);
    }

    function getPermit2() external view returns (address) {
        return address(permit2);
    }

    function getNativeAddress() external pure returns (address) {
        return nativeAddress;
    }

    function getWethAddress() external view returns (address) {
        return wethAddress;
    }

    function getTotalIntents() external view returns (uint256) {
        return totalIntents;
    }

    function getMaxTokenAllowedWithoutMultiSig()
        external
        view
        returns (uint256)
    {
        return maxTokenAllowedWithoutMultiSig;
    }

    function getMaxETHAllowedWithoutMultiSig() external view returns (uint256) {
        return maxETHAllowedWithoutMultiSig;
    }
}