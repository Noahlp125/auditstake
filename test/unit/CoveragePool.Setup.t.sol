// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CoveragePool} from "../../src/CoveragePool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract CoveragePoolSetupTest is Test {
    MockERC20 stakeToken;
    MockERC20 premiumToken;
    CoveragePool pool;

    address registry = makeAddr("registry");
    address claimManager = makeAddr("claimManager");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant COOLDOWN = 7 days;
    uint256 constant WINDOW = 2 days;
    uint16 constant MAX_SLASH_BPS = 5_000;

    function setUp() public {
        stakeToken = new MockERC20("Stake", "STK");
        premiumToken = new MockERC20("Premium", "PRM");
        pool = _deploy(stakeToken, premiumToken, registry, claimManager, WINDOW, MAX_SLASH_BPS);

        stakeToken.mint(alice, 1_000 ether);
        vm.prank(alice);
        stakeToken.approve(address(pool), type(uint256).max);
    }

    function _deploy(IERC20 a, IERC20 r, address reg, address cm, uint256 window, uint16 bps)
        internal
        returns (CoveragePool)
    {
        return new CoveragePool(a, r, reg, cm, COOLDOWN, window, bps, "AuditStake Pool", "asPOOL");
    }

    // ─────────────────── Configuracion correcta ───────────────────

    function test_ConstructorSetsConfig() public view {
        assertEq(pool.asset(), address(stakeToken));
        assertEq(address(pool.rewardToken()), address(premiumToken));
        assertEq(pool.registry(), registry);
        assertEq(pool.claimManager(), claimManager);
        assertEq(pool.cooldownPeriod(), COOLDOWN);
        assertEq(pool.unstakeWindow(), WINDOW);
        assertEq(pool.maxSlashBps(), MAX_SLASH_BPS);
    }

    function test_SharesHave6ExtraDecimals() public view {
        assertEq(pool.decimals(), 18 + 6);
    }

    // ─────────────────── Validaciones del constructor ───────────────────

    function test_RevertWhen_RewardTokenEqualsAsset() public {
        vm.expectRevert(CoveragePool.SameToken.selector);
        _deploy(stakeToken, stakeToken, registry, claimManager, WINDOW, MAX_SLASH_BPS);
    }

    function test_RevertWhen_ZeroRegistry() public {
        vm.expectRevert(CoveragePool.ZeroAddress.selector);
        _deploy(stakeToken, premiumToken, address(0), claimManager, WINDOW, MAX_SLASH_BPS);
    }

    function test_RevertWhen_ZeroClaimManager() public {
        vm.expectRevert(CoveragePool.ZeroAddress.selector);
        _deploy(stakeToken, premiumToken, registry, address(0), WINDOW, MAX_SLASH_BPS);
    }

    function test_RevertWhen_SlashBpsIsZero() public {
        vm.expectRevert(CoveragePool.InvalidBps.selector);
        _deploy(stakeToken, premiumToken, registry, claimManager, WINDOW, 0);
    }

    function test_RevertWhen_SlashBpsAbove100Percent() public {
        vm.expectRevert(CoveragePool.InvalidBps.selector);
        _deploy(stakeToken, premiumToken, registry, claimManager, WINDOW, 10_001);
    }

    function test_RevertWhen_UnstakeWindowIsZero() public {
        vm.expectRevert(CoveragePool.InvalidDuration.selector);
        _deploy(stakeToken, premiumToken, registry, claimManager, 0, MAX_SLASH_BPS);
    }

    // ─────────────────── Deposito y shares ───────────────────

    function test_DepositMintsSharesWithOffset() public {
        vm.prank(alice);
        uint256 shares = pool.deposit(100 ether, alice);

        assertEq(shares, 100 ether * 1e6);
        assertEq(pool.balanceOf(alice), shares);
        assertEq(pool.totalAssets(), 100 ether);
    }

    function test_RevertWhen_TransferShares() public {
        vm.prank(alice);
        uint256 shares = pool.deposit(100 ether, alice);

        vm.prank(alice);
        vm.expectRevert(CoveragePool.NonTransferable.selector);
        pool.transfer(bob, shares);
    }

    function test_RevertWhen_TransferFromShares() public {
        vm.prank(alice);
        uint256 shares = pool.deposit(100 ether, alice);
        vm.prank(alice);
        pool.approve(bob, shares);

        vm.prank(bob);
        vm.expectRevert(CoveragePool.NonTransferable.selector);
        pool.transferFrom(alice, bob, shares);
    }
}