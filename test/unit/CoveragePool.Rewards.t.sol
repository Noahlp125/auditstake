// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CoveragePool} from "../../src/CoveragePool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract CoveragePoolRewardsTest is Test {
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
    uint256 constant TOLERANCE = 1e12; // 0.0001% de error relativo

    function setUp() public {
        stakeToken = new MockERC20("Stake", "STK");
        premiumToken = new MockERC20("Premium", "PRM");
        pool = new CoveragePool(
            stakeToken, premiumToken, registry, claimManager, COOLDOWN, WINDOW, MAX_SLASH_BPS, "AuditStake Pool", "asPOOL"
        );

        stakeToken.mint(alice, 1_000 ether);
        stakeToken.mint(bob, 1_000 ether);
        premiumToken.mint(registry, 1_000_000 ether);

        vm.prank(alice);
        stakeToken.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        stakeToken.approve(address(pool), type(uint256).max);
        vm.prank(registry);
        premiumToken.approve(address(pool), type(uint256).max);
    }

    function _stake(address who, uint256 amount) internal {
        vm.prank(who);
        pool.deposit(amount, who);
    }

    function _notify(uint256 amount, uint256 duration) internal {
        vm.prank(registry);
        pool.notifyRewardAmount(amount, duration);
    }

    // ─────────────────── Permisos y validaciones ───────────────────

    function test_RevertWhen_NotRegistryNotifies() public {
        vm.prank(alice);
        vm.expectRevert(CoveragePool.NotRegistry.selector);
        pool.notifyRewardAmount(100 ether, 1 days);
    }

    function test_RevertWhen_NotifyZeroAmount() public {
        vm.prank(registry);
        vm.expectRevert(CoveragePool.ZeroAmount.selector);
        pool.notifyRewardAmount(0, 1 days);
    }

    function test_RevertWhen_NotifyZeroDuration() public {
        vm.prank(registry);
        vm.expectRevert(CoveragePool.InvalidDuration.selector);
        pool.notifyRewardAmount(100 ether, 0);
    }

    function test_NotifySetsPeriod() public {
        _notify(1_000 ether, 10 days);
        assertEq(pool.periodFinish(), block.timestamp + 10 days);
        assertEq(premiumToken.balanceOf(address(pool)), 1_000 ether);
    }

    // ─────────────────── Reparto ───────────────────

    function test_SingleStakerEarnsEverything() public {
        _stake(alice, 100 ether);
        _notify(1_000 ether, 10 days);
        vm.warp(block.timestamp + 10 days);

        assertApproxEqRel(pool.earned(alice), 1_000 ether, TOLERANCE);
    }

    function test_RewardsAccrueLinearly() public {
        _stake(alice, 100 ether);
        _notify(1_000 ether, 10 days);
        vm.warp(block.timestamp + 3 days);

        assertApproxEqRel(pool.earned(alice), 300 ether, TOLERANCE);
    }

    function test_RewardsSplitProportionally() public {
        _stake(alice, 300 ether);
        _stake(bob, 100 ether);
        _notify(1_000 ether, 10 days);
        vm.warp(block.timestamp + 10 days);

        assertApproxEqRel(pool.earned(alice), 750 ether, TOLERANCE);
        assertApproxEqRel(pool.earned(bob), 250 ether, TOLERANCE);
    }

    /// @dev Bob entra a mitad del periodo: solo cobra desde que entra.
    ///      Dias 0-5: alice sola -> 500. Dias 5-10: 50/50 -> 250 cada uno.
    function test_LateStakerOnlyEarnsFromEntry() public {
        _stake(alice, 100 ether);
        _notify(1_000 ether, 10 days);

        vm.warp(block.timestamp + 5 days);
        _stake(bob, 100 ether);
        vm.warp(block.timestamp + 5 days);

        assertApproxEqRel(pool.earned(alice), 750 ether, TOLERANCE);
        assertApproxEqRel(pool.earned(bob), 250 ether, TOLERANCE);
    }

    function test_NoRewardsAfterPeriodEnds() public {
        _stake(alice, 100 ether);
        _notify(1_000 ether, 10 days);
        vm.warp(block.timestamp + 10 days);
        uint256 atEnd = pool.earned(alice);

        vm.warp(block.timestamp + 30 days);
        assertEq(pool.earned(alice), atEnd);
    }

    /// @dev Nueva prima a mitad de periodo: lo pendiente se suma a lo nuevo.
    ///      Dia 5: quedan 500 sin repartir + 1000 nuevos = 1500 en 10 dias.
    function test_TopUpAddsLeftover() public {
        _stake(alice, 100 ether);
        _notify(1_000 ether, 10 days);
        vm.warp(block.timestamp + 5 days);

        _notify(1_000 ether, 10 days);
        vm.warp(block.timestamp + 10 days);

        assertApproxEqRel(pool.earned(alice), 2_000 ether, TOLERANCE);
    }

    // ─────────────────── Cobro ───────────────────

    function test_ClaimRewardsTransfersAndResets() public {
        _stake(alice, 100 ether);
        _notify(1_000 ether, 10 days);
        vm.warp(block.timestamp + 10 days);

        vm.prank(alice);
        uint256 got = pool.claimRewards();

        assertApproxEqRel(got, 1_000 ether, TOLERANCE);
        assertEq(premiumToken.balanceOf(alice), got);
        assertEq(pool.earned(alice), 0);
        assertEq(pool.rewards(alice), 0);
    }

    function test_ClaimTwiceDoesNotPayTwice() public {
        _stake(alice, 100 ether);
        _notify(1_000 ether, 10 days);
        vm.warp(block.timestamp + 10 days);

        vm.startPrank(alice);
        pool.claimRewards();
        uint256 second = pool.claimRewards();
        vm.stopPrank();

        assertEq(second, 0);
    }

    /// @dev Al retirar el stake, lo ya devengado no se pierde.
    function test_RewardsSurviveWithdrawal() public {
        _stake(alice, 100 ether);
        _notify(1_000 ether, 10 days);

        vm.prank(alice);
        pool.startCooldown();
        vm.warp(block.timestamp + COOLDOWN);
        vm.prank(alice);
        pool.withdraw(100 ether, alice, alice);

        uint256 owed = pool.earned(alice);
        assertApproxEqRel(owed, 700 ether, TOLERANCE); // 7 de 10 dias

        vm.warp(block.timestamp + 3 days); // ya fuera: no gana mas
        assertEq(pool.earned(alice), owed);

        vm.prank(alice);
        assertEq(pool.claimRewards(), owed);
    }

    // ─────────────────── Ataque: just-in-time staking ───────────────────

    /// @dev Un atacante ve en el mempool que llega una prima grande y mete
    ///      stake justo antes para quedarse con parte. Con el reparto en
    ///      streaming no gana nada que no se haya ganado estando expuesto:
    ///      si sale en cuanto puede (7 dias de cooldown), solo cobra por esos dias.
    function test_JustInTimeStakeOnlyEarnsTimeExposed() public {
        _stake(alice, 100 ether);

        _stake(bob, 100 ether); // bob entra justo antes de la prima
        _notify(1_000 ether, 100 days);

        vm.prank(bob);
        pool.startCooldown();
        vm.warp(block.timestamp + COOLDOWN);
        vm.prank(bob);
        pool.withdraw(100 ether, bob, bob);

        // 7 de 100 dias, mitad del pool: 1000 * 7/100 / 2 = 35
        assertApproxEqRel(pool.earned(bob), 35 ether, TOLERANCE);
    }

    // ─────────────────── Fuzz ───────────────────

    /// @dev Stake enorme + recompensa pequena + checkpoints diarios.
    ///      Con PRECISION = 1e18 este test fallaria por truncamiento.
    function testFuzz_NoPrecisionLossWithLargeStake(uint256 stake, uint256 reward) public {
        stake = bound(stake, 1 ether, 1e12 ether);
        reward = bound(reward, 1 ether, 1e6 ether);
        stakeToken.mint(alice, stake);
        _stake(alice, stake);

        _notify(reward, 30 days);
        for (uint256 i; i < 30; i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(alice);
            pool.claimRewards(); // fuerza un checkpoint cada dia
        }
        assertApproxEqRel(premiumToken.balanceOf(alice), reward, TOLERANCE);
    }

    function testFuzz_RewardsNeverExceedPremium(uint256 a, uint256 b, uint256 dt) public {
        _stake(alice, bound(a, 1 ether, 1_000 ether));
        _stake(bob, bound(b, 1 ether, 1_000 ether));
        _notify(1_000 ether, 10 days);
        vm.warp(block.timestamp + bound(dt, 0, 20 days));

        assertLe(pool.earned(alice) + pool.earned(bob), 1_000 ether);
    }
}
