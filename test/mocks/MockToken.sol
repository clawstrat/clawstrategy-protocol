// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IClankerToken} from "../../src/interfaces/IClankerToken.sol";

contract MockToken is ERC20, IClankerToken {
    address public admin;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 100_000_000_000 * 10 ** decimals());
        admin = msg.sender;
    }

    function updateAdmin(address admin_) external {
        admin = admin_;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

