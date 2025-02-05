// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin/access/Ownable2Step.sol";

/// @title Kaito
contract Kaito is ERC20Permit, Ownable2Step {
    address public minter;

    error OnlyMinter();

    event SetMinter(address indexed prevMinter, address indexed newMinter);

    modifier onlyMinter() {
        if (msg.sender != minter) revert OnlyMinter();
        _;
    }

    constructor(string memory name_, string memory symbol_) ERC20Permit(name_) ERC20(name_, symbol_) {}

    function setMinter(address newMinter) external onlyOwner {
        emit SetMinter(minter, newMinter);
        minter = newMinter;
    }

    function renounceOwnership() public view override onlyOwner {
        revert();
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
