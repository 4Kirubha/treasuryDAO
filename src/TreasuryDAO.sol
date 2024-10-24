// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {SpokePoolInterface} from "./interfaces/ISpokePool.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IMultiSig} from "./interfaces/IMultiSig.sol";
import {console} from "forge-std/console.sol";

contract TreasuryDAO is Ownable {
    error InvalidSpender();
    error InvalidIntent();
    error InvalidZeroChainID();
    error ZeroAddress();
    error NotEnoughNative(uint256 amount);
    error NotAllowedToTransfer(uint256 index);

    event ScheduledIntent(address user, Intent intent);

    struct Intent {
        address token;
        uint256 amount;
        address recipient;
        uint256 destinationChainId;
        uint256 executeAt;
        uint64 relayerFee;
        bool executed;
    }

    IAllowanceTransfer private immutable permit2;
    SpokePoolInterface private immutable spokePool;
    IMultiSig private multiSig;
    uint256 private totalIntents;
    uint256 private immutable maxTokenAllowedWithoutMultiSig;
    uint256 private immutable maxETHAllowedWithoutMultiSig;
    address private constant nativeAddress =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private immutable wethAddress;
    mapping(uint256 intentNumber => address user) public users;
    mapping(address user => Intent intent) public intents;
    mapping(uint256 chainId => bool supported) public supportedChains;

    constructor(
        address _permit2,
        address _spokePool,
        address _wethAddress,
        uint256[] memory chainIds,
        uint256 _maxAllowedToken,
        uint256 _maxAllowedETH
    ) Ownable() {
        if (_spokePool == address(0) || _permit2 == address(0)) {
            revert ZeroAddress();
        }

        uint256 arrayLength = chainIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            if (chainIds[i] == 0) revert InvalidZeroChainID();
            supportedChains[chainIds[i]] = true;
        }

        permit2 = IAllowanceTransfer(_permit2);
        spokePool = SpokePoolInterface(_spokePool);
        wethAddress = _wethAddress;
        maxTokenAllowedWithoutMultiSig = _maxAllowedToken;
        maxETHAllowedWithoutMultiSig = _maxAllowedETH;
    }

    function setMultiSig(address _multiSig) external onlyOwner {
        if (_multiSig == address(0)) revert ZeroAddress();
        multiSig = IMultiSig(_multiSig);
    }

    function scheduleOrModifyIntent(Intent memory intent) external payable {
        if (
            intent.token == address(0) ||
            intent.amount == 0 ||
            intent.recipient == address(0) ||
            intent.executeAt <= block.timestamp ||
            intent.destinationChainId == block.chainid ||
            // intent.relayerFee > (intent.amount * 50) / 100 ||
            !supportedChains[intent.destinationChainId]
        ) revert InvalidIntent();

        if (intent.token == nativeAddress && msg.value < intent.amount) {
            revert NotEnoughNative(msg.value);
        }

        if (intents[msg.sender].amount == 0) {
            users[totalIntents] = msg.sender;
            totalIntents++;
        }
        intent.executed = false;
        intents[msg.sender] = intent;

        emit ScheduledIntent(msg.sender, intent);
    }

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

    function triggerIntent(uint256[] memory intentsToTrigger) external {
        bytes memory validIntends = abi.encode(intentsToTrigger);
        performUpkeep(validIntends);
    }

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

    function _crossChainTransfer(Intent memory intent) internal {
        uint256 ethValue;
        if (intent.token == nativeAddress) {
            ethValue = intent.amount + intent.relayerFee;
            intent.token = wethAddress;
        } else {
            ethValue = intent.relayerFee;
            IERC20(intent.token).approve(address(spokePool), intent.amount);
        }
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
