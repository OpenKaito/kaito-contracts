pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { veKAITO } from "contracts/veKAITO.sol";
import { IveKAITO } from "contracts/interfaces/IveKAITO.sol";
import { ERC20Mintable } from "test/utils/ERC20Mintable.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";

contract veKAITOTest is Test {
    using SafeERC20 for IERC20;
    using BalanceSnapshot for Snapshot;

    address owner = makeAddr("owner");
    address blacklistManager = makeAddr("blacklistManager");
    address initialRewarder = makeAddr("initialRewarder");
    address user = makeAddr("user");

    ERC20Mintable kaito;
    veKAITO vekaito;

    function setUp() public {
        kaito = new ERC20Mintable("Kaito", "KAITO");
        vekaito = new veKAITO(IERC20(kaito), initialRewarder, owner);
        deal(initialRewarder, 1000 ether);
        deal(user, 1000 ether);

        kaito.mint(initialRewarder, 100000 ether);
        vm.startPrank(initialRewarder);
        IERC20(kaito).safeApprove(address(vekaito), type(uint256).max);
        vm.stopPrank();

        kaito.mint(user, 100000 ether);
        vm.startPrank(user);
        IERC20(kaito).safeApprove(address(vekaito), type(uint256).max);
        vm.stopPrank();

        vm.label(owner, "owner");
        vm.label(blacklistManager, "blacklistManager");
        vm.label(initialRewarder, "initialRewarder");
        vm.label(user, "user");
    }

    function testStake() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        uint256 shares = vekaito.deposit(amount, user);
        require(shares == amount, "should mint 1:1 first time");
        require(vekaito.totalAssets() == amount, "incorrect total asset");
    }

    function testCooldownAndClaim() public {
        Snapshot memory assetBalance = BalanceSnapshot.take({ owner: user, token: address(kaito) });
        Snapshot memory shareBalance = BalanceSnapshot.take({ owner: user, token: address(vekaito) });

        uint256 amount = 1 ether;
        vm.startPrank(user);
        uint256 shares = vekaito.deposit(amount, user);
        assetBalance.assertChange(-int256(amount));
        shareBalance.assertChange(int256(shares));

        vekaito.cooldownShares(shares);
        vm.warp(block.timestamp + 7 days);
        vekaito.claimFromAP(user);
        vm.stopPrank();

        assetBalance.assertChange(0);
        shareBalance.assertChange(0);
    }

    function testCooldownBeforeMature() public {
        uint256 amount = 1 ether;
        vm.startPrank(user);
        uint256 shares = vekaito.deposit(amount, user);

        vekaito.cooldownShares(shares);
        vm.warp(block.timestamp + 7 days - 1);
        vm.expectRevert(IveKAITO.ClaimNotMature.selector);
        vekaito.claimFromAP(user);
        vm.stopPrank();
    }

    function testCooldownWhileCooling() public {
        uint256 amount = 20 ether;
        vm.startPrank(user);
        vekaito.deposit(amount, user);

        vekaito.cooldownShares(10 ether);
        uint104 cdEnd;
        uint152 cdAmount;
        (cdEnd, cdAmount) = vekaito.cooldowns(user);
        require(cdEnd == block.timestamp + 7 days, "incorrect cooldown end");
        require(cdAmount == 10 ether, "incorrect cooldown amount");
        vm.warp(block.timestamp + 1 days);
        (cdEnd, cdAmount) = vekaito.cooldowns(user);
        require(cdEnd == block.timestamp + 6 days, "incorrect cooldown end");
        require(cdAmount == 10 ether, "incorrect cooldown amount");
        vekaito.cooldownShares(10 ether);
        (cdEnd, cdAmount) = vekaito.cooldowns(user);
        require(cdEnd == block.timestamp + 7 days, "incorrect cooldown end");
        require(cdAmount == 20 ether, "incorrect cooldown amount");
        vm.stopPrank();
    }

    function testTransferInRewards() public {
        uint256 rewardAmount = 200 ether;
        vm.expectEmit(true, true, true, true);
        emit IveKAITO.RewardsReceived(rewardAmount);
        vm.prank(initialRewarder);
        vekaito.transferInRewards(rewardAmount);
        require(vekaito.totalAssets() == 0, "incorrect total asset");
        require(vekaito.getUnvestedAmount() == rewardAmount, "incorrect unvested asset");

        uint256 amount = 50 ether;
        vm.startPrank(user);
        vekaito.deposit(amount, user);
        require(vekaito.totalAssets() == amount, "incorrect total asset");

        vm.warp(block.timestamp + 30 days);
        require(vekaito.totalAssets() == amount + rewardAmount, "incorrect total asset");
        require(vekaito.getUnvestedAmount() == 0, "incorrect unvested asset");
    }

    function testSetCooldownDuration() public {
        uint256 amount = 10 ether;
        vm.startPrank(user);
        vekaito.deposit(amount, user);

        vm.expectRevert(IveKAITO.OperationNotAllowed.selector);
        vekaito.withdraw(1 ether, user, user);

        vm.expectRevert(IveKAITO.OperationNotAllowed.selector);
        vekaito.redeem(1 ether, user, user);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IveKAITO.CooldownDurationUpdated(7 days, 0);
        vekaito.setCooldownDuration(0);

        vm.startPrank(user);
        vekaito.withdraw(1 ether, user, user);
        vekaito.redeem(1 ether, user, user);
        vm.stopPrank();
    }

    function testBlacklist() public {
        vm.prank(user);
        vekaito.deposit(10 ether, user);

        bytes32 BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");
        vm.prank(owner);
        vekaito.grantRole(BLACKLIST_MANAGER_ROLE, blacklistManager);

        // SOFT_RESTRICTED_STAKER_ROLE can do anything but stake
        vm.prank(blacklistManager);
        vekaito.addToBlacklist(user, false);
        vm.startPrank(user);
        vm.expectRevert(IveKAITO.OperationNotAllowed.selector);
        vekaito.deposit(5 ether, user);
        vekaito.cooldownAssets(1 ether);
        vekaito.transfer(owner, 1 ether);
        vm.stopPrank();

        // FULL_RESTRICTED_STAKER_ROLE can't do anything
        vm.prank(blacklistManager);
        vekaito.addToBlacklist(user, true);
        vm.startPrank(user);
        vm.expectRevert(IveKAITO.OperationNotAllowed.selector);
        vekaito.deposit(5 ether, user);
        vm.expectRevert(IveKAITO.OperationNotAllowed.selector);
        vekaito.cooldownAssets(1 ether);
        vm.expectRevert(IveKAITO.OperationNotAllowed.selector);
        vekaito.transfer(owner, 1 ether);
        vm.stopPrank();
    }
}
