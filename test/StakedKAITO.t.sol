pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { StakedKAITO } from "contracts/StakedKAITO.sol";
import { IStakedKAITO } from "contracts/interfaces/IStakedKAITO.sol";
import { ERC20Mintable } from "test/utils/ERC20Mintable.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";

contract StakedKAITOTest is Test {
    using SafeERC20 for IERC20;
    using BalanceSnapshot for Snapshot;

    address owner = makeAddr("owner");
    address blacklistManager = makeAddr("blacklistManager");
    address initialRewarder = makeAddr("initialRewarder");
    address user = makeAddr("user");

    ERC20Mintable kaito;
    StakedKAITO sKAITO;

    function setUp() public {
        kaito = new ERC20Mintable("Kaito", "KAITO");
        sKAITO = new StakedKAITO(IERC20(kaito), initialRewarder, owner);
        deal(initialRewarder, 1000 ether);
        deal(user, 1000 ether);

        kaito.mint(initialRewarder, 100000 ether);
        vm.startPrank(initialRewarder);
        IERC20(kaito).safeApprove(address(sKAITO), type(uint256).max);
        vm.stopPrank();

        kaito.mint(user, 100000 ether);
        vm.startPrank(user);
        IERC20(kaito).safeApprove(address(sKAITO), type(uint256).max);
        vm.stopPrank();

        vm.label(owner, "owner");
        vm.label(blacklistManager, "blacklistManager");
        vm.label(initialRewarder, "initialRewarder");
        vm.label(user, "user");
    }

    function testStake() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        uint256 shares = sKAITO.deposit(amount, user);
        require(shares == amount, "should mint 1:1 first time");
        require(sKAITO.totalAssets() == amount, "incorrect total asset");
    }

    function testCooldownAndClaim() public {
        Snapshot memory assetBalance = BalanceSnapshot.take({ owner: user, token: address(kaito) });
        Snapshot memory shareBalance = BalanceSnapshot.take({ owner: user, token: address(sKAITO) });

        uint256 amount = 1 ether;
        vm.startPrank(user);
        uint256 shares = sKAITO.deposit(amount, user);
        assetBalance.assertChange(-int256(amount));
        shareBalance.assertChange(int256(shares));

        sKAITO.cooldownShares(shares);
        vm.warp(block.timestamp + 7 days);
        sKAITO.claimFromAP(user);
        vm.stopPrank();

        assetBalance.assertChange(0);
        shareBalance.assertChange(0);
    }

    function testCooldownBeforeMature() public {
        uint256 amount = 1 ether;
        vm.startPrank(user);
        uint256 shares = sKAITO.deposit(amount, user);

        sKAITO.cooldownShares(shares);
        vm.warp(block.timestamp + 7 days - 1);
        vm.expectRevert(IStakedKAITO.ClaimNotMature.selector);
        sKAITO.claimFromAP(user);
        vm.stopPrank();
    }

    function testCooldownWhileCooling() public {
        uint256 amount = 20 ether;
        vm.startPrank(user);
        sKAITO.deposit(amount, user);

        sKAITO.cooldownShares(10 ether);
        uint104 cdEnd;
        uint152 cdAmount;
        (cdEnd, cdAmount) = sKAITO.cooldowns(user);
        require(cdEnd == block.timestamp + 7 days, "incorrect cooldown end");
        require(cdAmount == 10 ether, "incorrect cooldown amount");
        vm.warp(block.timestamp + 1 days);
        (cdEnd, cdAmount) = sKAITO.cooldowns(user);
        require(cdEnd == block.timestamp + 6 days, "incorrect cooldown end");
        require(cdAmount == 10 ether, "incorrect cooldown amount");
        sKAITO.cooldownShares(10 ether);
        (cdEnd, cdAmount) = sKAITO.cooldowns(user);
        require(cdEnd == block.timestamp + 7 days, "incorrect cooldown end");
        require(cdAmount == 20 ether, "incorrect cooldown amount");
        vm.stopPrank();
    }

    function testTransferInRewards() public {
        uint256 rewardAmount = 200 ether;
        vm.expectEmit(true, true, true, true);
        emit IStakedKAITO.RewardsReceived(rewardAmount);
        vm.prank(initialRewarder);
        sKAITO.transferInRewards(rewardAmount);
        require(sKAITO.totalAssets() == 0, "incorrect total asset");
        require(sKAITO.getUnvestedAmount() == rewardAmount, "incorrect unvested asset");

        uint256 amount = 50 ether;
        vm.startPrank(user);
        sKAITO.deposit(amount, user);
        require(sKAITO.totalAssets() == amount, "incorrect total asset");

        vm.warp(block.timestamp + 30 days);
        require(sKAITO.totalAssets() == amount + rewardAmount, "incorrect total asset");
        require(sKAITO.getUnvestedAmount() == 0, "incorrect unvested asset");
    }

    function testSetCooldownDuration() public {
        uint256 amount = 10 ether;
        vm.startPrank(user);
        sKAITO.deposit(amount, user);

        vm.expectRevert(IStakedKAITO.OperationNotAllowed.selector);
        sKAITO.withdraw(1 ether, user, user);

        vm.expectRevert(IStakedKAITO.OperationNotAllowed.selector);
        sKAITO.redeem(1 ether, user, user);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IStakedKAITO.CooldownDurationUpdated(7 days, 0);
        sKAITO.setCooldownDuration(0);

        vm.startPrank(user);
        sKAITO.withdraw(1 ether, user, user);
        sKAITO.redeem(1 ether, user, user);
        vm.stopPrank();
    }

    function testBlacklist() public {
        vm.prank(user);
        sKAITO.deposit(10 ether, user);

        bytes32 BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");
        vm.prank(owner);
        sKAITO.grantRole(BLACKLIST_MANAGER_ROLE, blacklistManager);

        // SOFT_RESTRICTED_STAKER_ROLE can do anything but stake
        vm.prank(blacklistManager);
        sKAITO.addToBlacklist(user, false);
        vm.startPrank(user);
        vm.expectRevert(IStakedKAITO.OperationNotAllowed.selector);
        sKAITO.deposit(5 ether, user);
        sKAITO.cooldownAssets(1 ether);
        sKAITO.transfer(owner, 1 ether);
        vm.stopPrank();

        // FULL_RESTRICTED_STAKER_ROLE can't do anything
        vm.prank(blacklistManager);
        sKAITO.addToBlacklist(user, true);
        vm.startPrank(user);
        vm.expectRevert(IStakedKAITO.OperationNotAllowed.selector);
        sKAITO.deposit(5 ether, user);
        vm.expectRevert(IStakedKAITO.OperationNotAllowed.selector);
        sKAITO.cooldownAssets(1 ether);
        vm.expectRevert(IStakedKAITO.OperationNotAllowed.selector);
        sKAITO.transfer(owner, 1 ether);
        vm.stopPrank();
    }
}
