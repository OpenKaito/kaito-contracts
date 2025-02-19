// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IStakedKAITO {
    event RewardsReceived(uint256 amount);
    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amount);
    event CooldownDurationUpdated(uint24 previousDuration, uint24 newDuration);
    event VestingPeriodUpdated(uint24 previousPeriod, uint24 newPeriod);
    event Claim(address indexed holder, address indexed recipient, uint256 amount);
    event CooldownStarted(address indexed holder, uint256 assets, uint256 shares);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

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
    error InvalidVestingPeriod();

    function addToBlacklist(address target) external;

    function removeFromBlacklist(address target) external;

    function transferInRewards(uint256 amount) external;

    function rescueTokens(address token, uint256 amount, address to) external;

    function redistributeLockedAmount(address from, address to) external;

    function setCooldownDuration(uint24 duration) external;

    function setVestingPeriod(uint24 newVestingPeriod) external;

    function cooldownAssets(uint256 assets) external returns (uint256 shares);

    function cooldownShares(uint256 shares) external returns (uint256 assets);

    function claimFromAP(address recipient) external;

    function useNonce() external returns (uint256);

    function getUnvestedAmount() external view returns (uint256);
}
