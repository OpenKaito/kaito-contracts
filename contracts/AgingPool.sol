// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract AgingPool {
    using SafeERC20 for IERC20;

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
        IERC20(ASSET).safeTransfer(to, amount);
    }
}
