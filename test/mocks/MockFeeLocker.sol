// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerFeeLocker} from "../../src/interfaces/IClankerFeeLocker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockFeeLocker is IClankerFeeLocker {
    using SafeERC20 for IERC20;

    mapping(address feeOwner => mapping(address token => uint256 balance)) public feesToClaim;
    mapping(address depositor => bool isAllowed) public allowedDepositors;

    function addDepositor(address depositor) external {
        allowedDepositors[depositor] = true;
        emit AddDepositor(depositor);
    }

    function storeFees(address feeOwner, address token, uint256 amount) external {
        if (!allowedDepositors[msg.sender]) revert Unauthorized();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        feesToClaim[feeOwner][token] += amount;
        emit StoreTokens(msg.sender, feeOwner, token, feesToClaim[feeOwner][token], amount);
    }

    function claim(address feeOwner, address token) external {
        uint256 balance = feesToClaim[feeOwner][token];
        if (balance == 0) revert NoFeesToClaim();
        feesToClaim[feeOwner][token] = 0;
        IERC20(token).safeTransfer(feeOwner, balance);
        emit ClaimTokens(feeOwner, token, balance);
    }

    function availableFees(address feeOwner, address token) external view returns (uint256) {
        return feesToClaim[feeOwner][token];
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

