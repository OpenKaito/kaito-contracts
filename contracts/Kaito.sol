// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC20Permit.sol";

/// @title Kaito
contract Kaito is ERC20Permit {
    uint256 constant TOTALSUPPLY = 1e9 ether;
    constructor(string memory name_, string memory symbol_, address[] memory wallets, uint256[] memory amounts) ERC20Permit(name_) ERC20(name_, symbol_) {
        require(wallets.length == amounts.length, "array_length");
        for (uint256 i = 0; i < wallets.length; i++) {
            _mint(wallets[i], amounts[i]);
        }
        require(totalSupply() == TOTALSUPPLY, "supply_mismatch");
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
