// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

struct Snapshot {
    address owner;
    IERC20 token;
    int256 balanceBefore; // Assume max balance is type(int256).max
}

library BalanceSnapshot {
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant ZERO_ADDRESS = address(0);

    function take(address owner, address token) internal view returns (Snapshot memory) {
        uint256 balanceBefore;
        if (token == ETH_ADDRESS || token == ZERO_ADDRESS) {
            balanceBefore = owner.balance;
        } else {
            balanceBefore = IERC20(token).balanceOf(owner);
        }
        return Snapshot(owner, IERC20(token), int256(balanceBefore));
    }

    function _getBalanceAfter(Snapshot memory snapshot) internal view returns (int256) {
        if (address(snapshot.token) == ETH_ADDRESS || address(snapshot.token) == ZERO_ADDRESS) {
            return int256(snapshot.owner.balance);
        } else {
            return int256(snapshot.token.balanceOf(snapshot.owner));
        }
    }

    function assertChange(Snapshot memory snapshot, int256 expectedChange) internal view {
        int256 balanceAfter = _getBalanceAfter(snapshot);
        require(balanceAfter - snapshot.balanceBefore == expectedChange, "Not expected balance change");
    }

    function assertChangeGt(Snapshot memory snapshot, int256 expectedMinChange) internal view {
        int256 balanceAfter = _getBalanceAfter(snapshot);
        int256 balanceChange = balanceAfter - snapshot.balanceBefore;
        bool sameSign = (balanceChange >= int256(0) && expectedMinChange >= int256(0)) || (balanceChange <= int256(0) && expectedMinChange <= int256(0));
        require(sameSign, "Actual and expected change do not have the same sign");

        if (balanceChange > int256(0)) {
            require(balanceChange >= expectedMinChange, "Not expected balance change");
        } else {
            require(balanceChange < expectedMinChange, "Not expected balance change");
        }
    }
}
