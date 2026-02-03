// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IClankerToken {
    function updateAdmin(address admin_) external;

    function admin() external view returns (address);

    function burn(uint256 amount) external;
}

