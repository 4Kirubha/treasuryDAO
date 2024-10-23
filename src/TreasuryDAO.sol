// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {SpokePoolInterface} from "./interfaces/ISpokePool.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IMultiSig} from "./interfaces/IMultiSig.sol";

contract TreasuryDAO is Ownable{
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
    }

    IAllowanceTransfer immutable permit2;
    SpokePoolInterface immutable spokePool;
    IMultiSig public multiSig;
    uint256 private totalIntents;
    uint256 immutable maxAllowedWithoutMultiSig;
    mapping(uint256 intentNumber => address user) public users;
    mapping(address user => Intent intent) public intents;
    mapping(uint256 chainId => bool supported) public supportedChains;

    constructor(
        address _permit2,
        address _spokePool,
        uint256[] memory chainIds,
        uint256 _maxAllowed
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
        maxAllowedWithoutMultiSig = _maxAllowed;
    }

    function setMultiSig(address _multiSig) external onlyOwner{
        if(_multiSig == address(0)) revert ZeroAddress();
        multiSig = IMultiSig(_multiSig);
    }

    function scheduleOrModifyIntent(Intent memory intent) external payable {
        if (
            intent.token == address(0) ||
            intent.amount == 0 ||
            intent.recipient == address(0) ||
            intent.executeAt <= block.timestamp ||
            intent.relayerFee > (intent.amount * 50) / 100 ||
            !supportedChains[intent.destinationChainId]
        ) revert InvalidIntent();

        if (
            intent.token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE &&
            msg.value < (intent.amount + intent.relayerFee)
        ) {
            revert NotEnoughNative(msg.value);
        }
        if (intents[msg.sender].amount == 0) {
            totalIntents++;
            users[totalIntents] = msg.sender;
        }

        intents[msg.sender] = intent;

        emit ScheduledIntent(msg.sender, intent);
    }

    // function permitThroughPermit2(
    //     IAllowanceTransfer.PermitSingle calldata permitSingle,
    //     bytes calldata signature
    // ) public {
    //     if (permitSingle.spender != address(this)) revert InvalidSpender();
    //     permit2.permit(msg.sender, permitSingle, signature);
    // }

    // function transferToMe(address token, uint160 amount) public {
    //     permit2.transferFrom(msg.sender, address(this), amount, token);
    //     // ...Do cool stuff ...
    // }

    function permitAndTransferToMe(
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature,
        uint160 amount
    ) public {
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
        for (uint256 i = 0; i <= totalIntents; i++) {
            if (intents[users[i]].executeAt < block.timestamp) {
                ++numberofValidIntents;
            }
        }

        uint256[] memory validIntents = new uint256[](numberofValidIntents);
        uint256 index;
        for (uint256 i = 0; i <= totalIntents; i++) {
            if (intents[users[i]].executeAt < block.timestamp) {
                validIntents[index] = i;
                ++index;
            }
        }
        if (validIntents.length > 0) {
            upkeepNeeded = true;
            performData = abi.encode(validIntents);
        }
    }

    function performUpkeep(bytes memory performData) public {
        uint256[] memory validIntents = abi.decode(performData, (uint256[]));
        for (uint256 i = 0; i < validIntents.length; i++) {
            Intent memory intent = intents[users[validIntents[i]]];
            if (
                intent.amount < maxAllowedWithoutMultiSig &&
                intents[users[i]].executeAt < block.timestamp
            ) {
                _crossChainTransfer(intent);
            }
        }
    }

    function triggerIntent(uint256[] memory intentsToTrigger) external {
        bytes memory validIntends = abi.encode(intentsToTrigger);
        performUpkeep(validIntends);
    }

    function _crossChainTransfer(Intent memory intent) internal {
        uint256 ethValue;
        if (intent.token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            ethValue = intent.amount + intent.relayerFee;
        } else {
            ethValue = intent.relayerFee;
            IERC20(intent.token).approve(address(spokePool), intent.amount);
        }
        spokePool.deposit{value: ethValue}(
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
}
