// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin/access/Ownable2Step.sol";

/// @title Kaito
contract Kaito is ERC20Permit, Ownable2Step {
    uint256 constant TOTALSUPPLY = 1e27;
    constructor(string memory name_, string memory symbol_, address[] memory wallets, uint256[] memory amounts) ERC20Permit(name_) ERC20(name_, symbol_) {
        require(wallets.length == amounts.length, "array_length");
        for (uint256 i = 0; i < wallets.length; i++) {
            _mint(wallets[i], amounts[i]);
        }
        require(totalSupply() == TOTALSUPPLY, "supply_mismatch");
    }

    function renounceOwnership() public view override onlyOwner {
        revert();
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
