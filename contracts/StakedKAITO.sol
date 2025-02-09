// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin/security/ReentrancyGuard.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "./AgingPool.sol";
import "./SingleAdminAccessControl.sol";
import "./interfaces/IStakedKAITO.sol";

contract StakedKAITO is SingleAdminAccessControl, ReentrancyGuard, ERC20Permit, ERC4626, IStakedKAITO {
    using SafeERC20 for IERC20;

    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 lockedAmount;
    }

    uint24 public constant MAX_COOLDOWN_DURATION = 90 days;
    uint24 public constant MAX_VESTING_PERIOD = 90 days;
    uint256 private constant MIN_SHARES = 1 ether;
    bytes32 private constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    bytes32 private constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");
    bytes32 private constant BLACKLISTED_ROLE = keccak256("BLACKLISTED_ROLE");

    uint256 public vestingAmount;
    uint256 public lastDistributionTimestamp;
    mapping(address => UserCooldown) public cooldowns;
    uint24 public cooldownDuration;
    uint24 public vestingPeriod;
    AgingPool public immutable agingPool;

    modifier ensureCooldownOff() {
        if (cooldownDuration != 0) revert OperationNotAllowed();
        _;
    }

    modifier ensureCooldownOn() {
        if (cooldownDuration == 0) revert OperationNotAllowed();
        _;
    }

    constructor(IERC20 _asset, address _initialRewarder, address _owner) ERC4626(_asset) ERC20("Staked KAITO", "sKAITO") ERC20Permit("sKAITO") {
        if (_owner == address(0) || _initialRewarder == address(0) || address(_asset) == address(0)) {
            revert InvalidZeroAddress();
        }
        agingPool = new AgingPool(address(this), address(_asset));
        _grantRole(REWARDER_ROLE, _initialRewarder);
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _updateCooldownDuration(7 days);
        _updateVestingPeriod(7 days);
    }

    function addToBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        if (target == owner()) revert CantBlacklistOwner();
        _grantRole(BLACKLISTED_ROLE, target);
    }

    function removeFromBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        _revokeRole(BLACKLISTED_ROLE, target);
    }

    function transferInRewards(uint256 amount) external nonReentrant onlyRole(REWARDER_ROLE) {
        if (amount == 0) revert InvalidAmount();
        _updateVestingAmount(amount);
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        emit RewardsReceived(amount);
    }

    function rescueTokens(address token, uint256 amount, address to) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(token) == asset()) revert InvalidToken();
        IERC20(token).safeTransfer(to, amount);
        emit TokensRescued(token, to, amount);
    }

    /**
     * @dev Burns the full restricted user amount and mints to the desired owner address.
     * @param from The address to burn the entire balance, with the BLACKLISTED_ROLE
     * @param to The address to mint the entire balance of "from" parameter.
     */
    function redistributeLockedAmount(address from, address to) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (hasRole(BLACKLISTED_ROLE, from) && !hasRole(BLACKLISTED_ROLE, to)) {
            uint256 shares = balanceOf(from);
            if (shares == 0) revert InvalidAmount();
            uint256 assets = previewRedeem(shares);
            _burn(from, shares);
            // to address of address(0) enables burning
            if (to == address(0)) {
                _updateVestingAmount(assets);
            } else {
                _mint(to, shares);
            }

            emit LockedAmountRedistributed(from, to, shares);
        } else {
            revert OperationNotAllowed();
        }
    }

    /// @notice Set cooldown duration. If cooldown duration is set to zero, the contract behavior changes to follow ERC4626 standard and disables cooldownShares and cooldownAssets methods. If cooldown duration is greater than zero, the ERC4626 withdrawal and redeem functions are disabled, breaking the ERC4626 standard, and enabling the cooldownShares and the cooldownAssets functions.
    /// @param duration Duration of the cooldown
    function setCooldownDuration(uint24 duration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateCooldownDuration(duration);
    }

    function setVestingPeriod(uint24 newVestingPeriod) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateVestingPeriod(newVestingPeriod);
    }

    function withdraw(uint256 assets, address recipient, address owner) public virtual override ensureCooldownOff returns (uint256) {
        return super.withdraw(assets, recipient, owner);
    }

    function redeem(uint256 shares, address recipient, address owner) public virtual override ensureCooldownOff returns (uint256) {
        return super.redeem(shares, recipient, owner);
    }

    // @dev withdraw with cooldown
    function cooldownAssets(uint256 assets) external ensureCooldownOn returns (uint256 shares) {
        if (assets > maxWithdraw(msg.sender)) revert ExcessiveWithdrawAmount();

        shares = previewWithdraw(assets);

        cooldowns[msg.sender].cooldownEnd = uint104(block.timestamp) + cooldownDuration;
        cooldowns[msg.sender].lockedAmount += uint152(assets);

        _withdraw(msg.sender, address(agingPool), msg.sender, assets, shares);
        emit CooldownStarted(msg.sender, assets, shares);
    }

    // @dev redeem with cooldown
    function cooldownShares(uint256 shares) external ensureCooldownOn returns (uint256 assets) {
        if (shares > maxRedeem(msg.sender)) revert ExcessiveRedeemAmount();

        assets = previewRedeem(shares);

        cooldowns[msg.sender].cooldownEnd = uint104(block.timestamp) + cooldownDuration;
        cooldowns[msg.sender].lockedAmount += uint152(assets);

        _withdraw(msg.sender, address(agingPool), msg.sender, assets, shares);
        emit CooldownStarted(msg.sender, assets, shares);
    }

    function claimFromAP(address recipient) external {
        UserCooldown storage userCooldown = cooldowns[msg.sender];
        uint256 lockedAmount = userCooldown.lockedAmount;

        if (block.timestamp >= userCooldown.cooldownEnd || cooldownDuration == 0) {
            userCooldown.cooldownEnd = 0;
            userCooldown.lockedAmount = 0;

            agingPool.withdraw(recipient, lockedAmount);
            emit Claim(msg.sender, recipient, lockedAmount);
        } else {
            revert ClaimNotMature();
        }
    }

    function useNonce() external override returns (uint256) {
        return _useNonce(msg.sender);
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - getUnvestedAmount();
    }

    function getUnvestedAmount() public view returns (uint256) {
        uint256 timeSinceLastDistribution = block.timestamp - lastDistributionTimestamp;

        if (timeSinceLastDistribution >= vestingPeriod) {
            return 0;
        }

        uint256 deltaT;
        unchecked {
            deltaT = (vestingPeriod - timeSinceLastDistribution);
        }
        return (deltaT * vestingAmount) / vestingPeriod;
    }

    /// @dev Necessary because both ERC20 (from ERC20Permit) and ERC4626 declare decimals()
    function decimals() public pure override(ERC4626, ERC20) returns (uint8) {
        return 18;
    }

    /**
     * @dev Remove renounce role access from AccessControl, to prevent users to resign roles.
     */
    function renounceRole(bytes32, address) public virtual override {
        revert OperationNotAllowed();
    }

    /// @notice ensures a small non-zero amount of shares does not remain, exposing to donation attack
    function _checkMinShares() internal view {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0 && _totalSupply < MIN_SHARES) revert MinSharesViolation();
    }

    function _deposit(address caller, address recipient, uint256 assets, uint256 shares) internal override nonReentrant {
        if (shares == 0 || assets == 0) revert InvalidAmount();

        super._deposit(caller, recipient, assets, shares);
        _checkMinShares();
    }

    function _withdraw(address caller, address recipient, address _owner, uint256 assets, uint256 shares) internal override nonReentrant {
        if (shares == 0 || assets == 0) revert InvalidAmount();
        if (hasRole(BLACKLISTED_ROLE, _owner) || hasRole(BLACKLISTED_ROLE, recipient)) {
            revert OperationNotAllowed();
        }

        super._withdraw(caller, recipient, _owner, assets, shares);
        _checkMinShares();
    }

    function _updateVestingAmount(uint256 newVestingAmount) internal {
        if (getUnvestedAmount() > 0) revert StillVesting();

        vestingAmount = newVestingAmount;
        lastDistributionTimestamp = block.timestamp;
    }

    function _updateCooldownDuration(uint24 duration) internal {
        if (duration > MAX_COOLDOWN_DURATION) revert InvalidDuration();

        uint24 previousDuration = cooldownDuration;
        cooldownDuration = duration;
        emit CooldownDurationUpdated(previousDuration, cooldownDuration);
    }

    function _updateVestingPeriod(uint24 newVestingPeriod) internal {
        if (getUnvestedAmount() > 0) revert StillVesting();
        if (newVestingPeriod > MAX_VESTING_PERIOD) revert InvalidVestingPeriod();
        emit VestingPeriodUpdated(vestingPeriod, newVestingPeriod);
        vestingPeriod = newVestingPeriod;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning. Disables transfers from or to of addresses with the FULL_RESTRICTED_STAKER_ROLE role.
     */

    function _beforeTokenTransfer(address from, address to, uint256) internal virtual override {
        if (hasRole(BLACKLISTED_ROLE, msg.sender)) {
            revert OperationNotAllowed();
        }
        if (hasRole(BLACKLISTED_ROLE, from) && to != address(0)) {
            revert OperationNotAllowed();
        }
        if (hasRole(BLACKLISTED_ROLE, to)) {
            revert OperationNotAllowed();
        }
    }
}
