// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../../src/interfaces/IClanker.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract MockClanker is IClanker {
    mapping(address => DeploymentInfo) public deploymentInfoForToken;
    bool public deprecated;

    function setDeprecated(bool _deprecated) external {
        deprecated = _deprecated;
    }

    address public nextTokenAddress;

    function setNextTokenAddress(address token) external {
        nextTokenAddress = token;
    }

    function deployToken(DeploymentConfig memory) external payable returns (address) {
        // Return the preset token address or generate one
        if (nextTokenAddress != address(0)) {
            address token = nextTokenAddress;
            nextTokenAddress = address(0); // Reset after use
            return token;
        }
        // Fallback: generate deterministic address
        return address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender)))));
    }

    function deployTokenZeroSupply(TokenConfig memory) external returns (address) {
        address token = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender)))));
        return token;
    }

    function tokenDeploymentInfo(address token) external view returns (DeploymentInfo memory) {
        return deploymentInfoForToken[token];
    }

    function setDeploymentInfo(address token, DeploymentInfo memory info) external {
        deploymentInfoForToken[token] = info;
    }

    // IOwnerAdmins interface
    function owner() external pure returns (address) {
        return address(0);
    }

    function admins(address) external pure returns (bool) {
        return false;
    }

    function setAdmin(address, bool) external {}
}

