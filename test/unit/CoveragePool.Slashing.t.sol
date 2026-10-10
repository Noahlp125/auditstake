// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {CoveragePool} from "../../src/CoveragePool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract CoveragePoolSlashingTest is Test {
    MockERC20 stakeToken;
    MockERC20 premiumToken;
    CoveragePool pool;

    address registry = makeAddr("registry");
    address claimManager = makeAddr("claimManager");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address victims = makeAddr("victims");

    uint256 constant COOLDOWN = 7 days;
    uint256 constant WINDOW = 2 days;
    uint16 constant MAX_SLASH_BPS = 5_000; // 50%

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

    function _freeze() internal {
        vm.prank(claimManager);
        pool.freeze();
    }

    function _slash(uint256 amount) internal {
        vm.prank(claimManager);
        pool.slash(amount, victims);
    }

    function _unfreeze() internal {
        vm.prank(claimManager);
        pool.unfreeze();
    }

    // ─────────────────── Permisos ───────────────────

    function test_RevertWhen_NotClaimManagerFreezes() public {
        vm.prank(alice);
        vm.expectRevert(CoveragePool.NotClaimManager.selector);
        pool.freeze();
    }

    function test_RevertWhen_NotClaimManagerSlashes() public {
        _stake(alice, 100 ether);
        _freeze();
        vm.prank(alice);
        vm.expectRevert(CoveragePool.NotClaimManager.selector);
        pool.slash(1 ether, alice);
    }

    function test_RevertWhen_NotClaimManagerUnfreezes() public {
        _freeze();
        vm.prank(alice);
        vm.expectRevert(CoveragePool.NotClaimManager.selector);
        pool.unfreeze();
    }

    // ─────────────────── Estados ───────────────────

    function test_FreezeTakesSnapshot() public {
        _stake(alice, 100 ether);
        _freeze();
        assertTrue(pool.frozen());
        assertEq(pool.frozenAssetsSnapshot(), 100 ether);
        assertEq(pool.slashedDuringFreeze(), 0);
    }

    function test_RevertWhen_FreezeTwice() public {
        _freeze();
        vm.prank(claimManager);
        vm.expectRevert(CoveragePool.PoolFrozen.selector);
        pool.freeze();
    }

    function test_RevertWhen_UnfreezeNotFrozen() public {
        vm.prank(claimManager);
        vm.expectRevert(CoveragePool.PoolNotFrozen.selector);
        pool.unfreeze();
    }

    function test_RevertWhen_SlashNotFrozen() public {
        _stake(alice, 100 ether);
        vm.prank(claimManager);
        vm.expectRevert(CoveragePool.PoolNotFrozen.selector);
        pool.slash(1 ether, victims);
    }

    function test_RevertWhen_SlashZero() public {
        _stake(alice, 100 ether);
        _freeze();
        vm.prank(claimManager);
        vm.expectRevert(CoveragePool.ZeroAmount.selector);
        pool.slash(0, victims);
    }

    function test_RevertWhen_SlashToZeroAddress() public {
        _stake(alice, 100 ether);
        _freeze();
        vm.prank(claimManager);
        vm.expectRevert(CoveragePool.ZeroAddress.selector);
        pool.slash(1 ether, address(0));
    }

    // ─────────────────── Congelado: nadie entra ni sale ───────────────────

    /// @dev Alice estaba justo en su ventana de retirada cuando se abre el claim:
    ///      no puede escapar del slash.
    function test_FrozenBlocksWithdrawEvenInsideWindow() public {
        _stake(alice, 100 ether);
        vm.prank(alice);
        pool.startCooldown();
        vm.warp(block.timestamp + COOLDOWN);
        assertTrue(pool.canWithdraw(alice));

        _freeze();

        assertFalse(pool.canWithdraw(alice));
        assertEq(pool.maxWithdraw(alice), 0);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, alice, 1 ether, 0)
        );
        pool.withdraw(1 ether, alice, alice);
    }

    /// @dev Bob no puede entrar durante el claim: ni diluye la perdida de
    ///      los responsables, ni paga por un exploit que no respaldo.
    function test_FrozenBlocksDeposits() public {
        _stake(alice, 100 ether);
        _freeze();

        assertEq(pool.maxDeposit(bob), 0);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, bob, 100 ether, 0));
        pool.deposit(100 ether, bob);
    }

    function test_UnfreezeRestoresOperations() public {
        _stake(alice, 100 ether);
        _freeze();
        _unfreeze();

        _stake(bob, 100 ether);
        assertEq(pool.totalAssets(), 200 ether);
    }

    // ─────────────────── Efecto del slash ───────────────────

    /// @dev 300 + 100 en el pool, slash de 200 (50%). Cada uno pierde la mitad.
    function test_SlashReducesShareValueProportionally() public {
        _stake(alice, 300 ether);
        _stake(bob, 100 ether);
        uint256 aliceShares = pool.balanceOf(alice);

        _freeze();
        _slash(200 ether);
        _unfreeze();

        assertEq(stakeToken.balanceOf(victims), 200 ether);
        assertEq(pool.totalAssets(), 200 ether);
        assertEq(pool.balanceOf(alice), aliceShares); // no se queman shares
        assertApproxEqAbs(pool.convertToAssets(pool.balanceOf(alice)), 150 ether, 1e6);
        assertApproxEqAbs(pool.convertToAssets(pool.balanceOf(bob)), 50 ether, 1e6);
    }

    /// @dev Tras el slash, alice retira y recibe el valor recortado.
    function test_WithdrawAfterSlashGetsReducedAmount() public {
        _stake(alice, 100 ether);
        _freeze();
        _slash(40 ether);
        _unfreeze();

        vm.prank(alice);
        pool.startCooldown();
        vm.warp(block.timestamp + COOLDOWN);

        uint256 shares = pool.balanceOf(alice);
        vm.prank(alice);
        uint256 got = pool.redeem(shares, alice, alice);

        assertApproxEqAbs(got, 60 ether, 1e6);
    }

    /// @dev Quien entra DESPUES de un slash paga el precio nuevo: no hereda la perdida.
    function test_NewStakerAfterSlashIsNotPenalized() public {
        _stake(alice, 100 ether);
        _freeze();
        _slash(50 ether);
        _unfreeze();

        _stake(bob, 100 ether);
        assertApproxEqAbs(pool.convertToAssets(pool.balanceOf(bob)), 100 ether, 1e6);
        assertApproxEqAbs(pool.convertToAssets(pool.balanceOf(alice)), 50 ether, 1e6);
    }

    // ─────────────────── Cap de slashing ───────────────────

    function test_RevertWhen_SlashAboveCap() public {
        _stake(alice, 100 ether);
        _freeze();
        vm.prank(claimManager);
        vm.expectRevert(abi.encodeWithSelector(CoveragePool.SlashExceedsCap.selector, 51 ether, 50 ether));
        pool.slash(51 ether, victims);
    }

    function test_SlashExactlyAtCap() public {
        _stake(alice, 100 ether);
        _freeze();
        _slash(50 ether);
        assertEq(pool.totalAssets(), 50 ether);
    }

    /// @dev Varios slashes pequenos no pueden sumar mas que el cap.
    function test_SlashCapIsCumulative() public {
        _stake(alice, 100 ether);
        _freeze();
        _slash(30 ether);
        vm.prank(claimManager);
        vm.expectRevert(abi.encodeWithSelector(CoveragePool.SlashExceedsCap.selector, 30 ether, 20 ether));
        pool.slash(30 ether, victims);
    }

    /// @dev El cap se calcula sobre la foto, no sobre los activos que van quedando.
    ///      Si fuera sobre lo que queda: 50 + 25 + 12.5... superaria el 50% total.
    function test_CapUsesSnapshotNotRemaining() public {
        _stake(alice, 100 ether);
        _freeze();
        _slash(25 ether);
        _slash(25 ether); // total 50 = cap exacto sobre la foto de 100
        assertEq(pool.slashedDuringFreeze(), 50 ether);

        vm.prank(claimManager);
        vm.expectRevert(abi.encodeWithSelector(CoveragePool.SlashExceedsCap.selector, 1, 0));
        pool.slash(1, victims);
    }

    /// @dev Un nuevo congelamiento empieza con el contador a cero y nueva foto.
    function test_NewFreezeResetsCounter() public {
        _stake(alice, 100 ether);
        _freeze();
        _slash(50 ether);
        _unfreeze();

        _freeze();
        assertEq(pool.frozenAssetsSnapshot(), 50 ether);
        assertEq(pool.slashedDuringFreeze(), 0);
        _slash(25 ether); // 50% de 50
        assertEq(pool.totalAssets(), 25 ether);
    }

    // ─────────────────── Interaccion con recompensas ───────────────────

    /// @dev La prima ya devengada es del auditor aunque haya un claim abierto.
    function test_ClaimRewardsWorksWhileFrozen() public {
        _stake(alice, 100 ether);
        vm.prank(registry);
        pool.notifyRewardAmount(100 ether, 1 days);
        vm.warp(block.timestamp + 1 days);

        _freeze();
        _slash(50 ether);

        vm.prank(alice);
        uint256 got = pool.claimRewards();
        assertApproxEqRel(got, 100 ether, 1e12);
    }

    /// @dev El slash recorta stake, no shares: el reparto de primas no cambia.
    function test_RewardsKeepAccruingAfterSlash() public {
        _stake(alice, 300 ether);
        _stake(bob, 100 ether);
        _freeze();
        _slash(200 ether);
        _unfreeze();

        vm.prank(registry);
        pool.notifyRewardAmount(1_000 ether, 10 days);
        vm.warp(block.timestamp + 10 days);

        assertApproxEqRel(pool.earned(alice), 750 ether, 1e12);
        assertApproxEqRel(pool.earned(bob), 250 ether, 1e12);
    }

    // ─────────────────── Fuzz ───────────────────

    /// @dev Para cualquier reparto y slash dentro del cap, las perdidas son
    ///      proporcionales y lo que sale nunca supera el cap.
    function testFuzz_SlashIsProportionalAndCapped(uint256 a, uint256 b, uint256 s) public {
        uint256 amtA = bound(a, 1 ether, 1_000 ether);
        uint256 amtB = bound(b, 1 ether, 1_000 ether);
        _stake(alice, amtA);
        _stake(bob, amtB);
        uint256 total = amtA + amtB;
        uint256 slashAmt = bound(s, 1, total * MAX_SLASH_BPS / 10_000);

        _freeze();
        _slash(slashAmt);

        uint256 remaining = total - slashAmt;
        assertEq(pool.totalAssets(), remaining);
        assertApproxEqAbs(pool.convertToAssets(pool.balanceOf(alice)), amtA * remaining / total, 1e7);
        assertApproxEqAbs(pool.convertToAssets(pool.balanceOf(bob)), amtB * remaining / total, 1e7);
        assertLe(stakeToken.balanceOf(victims), total * MAX_SLASH_BPS / 10_000);
    }
}
