// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IStakedKAITO {
    event RewardsReceived(uint256 amount);
    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amount);
    event CooldownDurationUpdated(uint24 previousDuration, uint24 newDuration);

    error ExcessiveRedeemAmount();
    error ExcessiveWithdrawAmount();
    error ClaimNotMature();
    error InvalidAmount();
    error InvalidDuration();
    error InvalidToken();
    error MinSharesViolation();
    error OperationNotAllowed();
    error StillVesting();
    error CantBlacklistOwner();
    error InvalidZeroAddress();

    function addToBlacklist(address target, bool isFullBlacklisting) external;

    function removeFromBlacklist(address target, bool isFullBlacklisting) external;

    function transferInRewards(uint256 amount) external;

    function rescueTokens(address token, uint256 amount, address to) external;

    function redistributeLockedAmount(address from, address to) external;

    function setCooldownDuration(uint24 duration) external;

    function cooldownAssets(uint256 assets) external returns (uint256 shares);

    function cooldownShares(uint256 shares) external returns (uint256 assets);

    function claimFromAP(address receiver) external;

    function getUnvestedAmount() external view returns (uint256);
}
