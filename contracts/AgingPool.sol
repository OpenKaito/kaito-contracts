// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/IERC20.sol";

contract AgingPool {
    address immutable VAULT;
    IERC20 immutable ASSET;

    error OnlyVault();

    constructor(address vault, address asset) {
        VAULT = vault;
        ASSET = IERC20(asset);
    }

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert OnlyVault();
        _;
    }

    function withdraw(address to, uint256 amount) external onlyVault {
        ASSET.transfer(to, amount);
    }
}
