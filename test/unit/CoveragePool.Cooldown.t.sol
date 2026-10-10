// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {CoveragePool} from "../../src/CoveragePool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract CoveragePoolCooldownTest is Test {
    MockERC20 stakeToken;
    MockERC20 premiumToken;
    CoveragePool pool;

    address registry = makeAddr ("registry");
    address claimManager = makeAddr("claimManager");
    address alice = makeAddr("alice");

    uint256 constant COOLDOWN = 7 days;
    uint256 constant WINDOW = 2 days;
    uint16 constant MAX_SLASH_BPS = 5_000;

    function setUp() public {
        stakeToken = new MockERC20("Stake", "STK");
        premiumToken = new MockERC20("Premium", "PRM");
        pool = new CoveragePool(
            stakeToken, premiumToken, registry, claimManager, COOLDOWN, WINDOW, MAX_SLASH_BPS, "AuditStake Pool", "asPOOL"
        );

        stakeToken.mint(alice, 1_000 ether);
        vm.prank(alice);
        stakeToken.approve(address(pool), type(uint256).max);
    }

    function _stake(uint256 amount) internal {
        vm.prank(alice);
        pool.deposit(amount, alice);
    }

    function _startCooldown() internal {
        vm.prank(alice);
        pool.startCooldown();
    }

    // Iniciar cooldown
    function test_StartCooldownRecordsTimestamp() public {
        _stake(100 ether);
        _startCooldown();
        assertEq(pool.cooldownStart(alice), block.timestamp);
    }

    function test_StartCooldownEmitsEvent() public {
        _stake(100 ether);
        vm.expectEmit(true, false, false, true);
        emit CoveragePool.CooldownStarted(alice, block.timestamp + COOLDOWN);
        _startCooldown();
    }

    function test_RevertWhen_StartCooldownWithoutStake() public {
        vm.prank(alice);
        vm.expectRevert(CoveragePool.ZeroAmount.selector);
        pool.startCooldown();
    }

    // ─────────────────── Retiradas bloqueadas ───────────────────

    function test_RevertWhen_WithdrawWithoutCooldown() public {
        _stake(100 ether);
        assertEq(pool.maxWithdraw(alice), 0);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, alice, 100 ether, 0)
        );
        pool.withdraw(100 ether, alice, alice);
    }

    function test_RevertWhen_WithdrawDuringCooldown() public {
        _stake(100 ether);
        _startCooldown();
        vm.warp(block.timestamp + COOLDOWN - 1); // falta 1 segundo

        assertFalse(pool.canWithdraw(alice));
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, alice, 100 ether, 0)
        );
        pool.withdraw(100 ether, alice, alice);
    }

    function test_RevertWhen_RedeemDuringCooldown() public {
        _stake(100 ether);
        uint256 shares = pool.balanceOf(alice);
        _startCooldown();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxRedeem.selector, alice, shares, 0));
        pool.redeem(shares, alice, alice);
    }

    function test_CannotWithdrawAfterWindowExpires() public {
        _stake(100 ether);
        _startCooldown();
        vm.warp(block.timestamp + COOLDOWN + WINDOW + 1); // ventana cerrada

        assertFalse(pool.canWithdraw(alice));
        assertEq(pool.maxWithdraw(alice), 0);
    }

    // ─────────────────── Retiradas permitidas ───────────────────

    function test_WithdrawAtWindowOpen() public {
        _stake(100 ether);
        _startCooldown();
        vm.warp(block.timestamp + COOLDOWN); // justo al abrirse

        vm.prank(alice);
        pool.withdraw(100 ether, alice, alice);

        assertEq(stakeToken.balanceOf(alice), 1_000 ether);
        assertEq(pool.balanceOf(alice), 0);
        assertEq(pool.cooldownStart(alice), 0); // se limpia al vaciar
    }

    function test_WithdrawAtLastSecondOfWindow() public {
        _stake(100 ether);
        _startCooldown();
        vm.warp(block.timestamp + COOLDOWN + WINDOW); // ultimo segundo valido

        assertTrue(pool.canWithdraw(alice));
        uint256 shares = pool.balanceOf(alice); // fuera del prank: ver nota
        vm.prank(alice);
        pool.redeem(shares, alice, alice);
        assertEq(stakeToken.balanceOf(alice), 1_000 ether);
    }

    function test_PartialWithdrawKeepsCooldown() public {
        _stake(100 ether);
        _startCooldown();
        uint256 started = pool.cooldownStart(alice);
        vm.warp(block.timestamp + COOLDOWN);

        vm.prank(alice);
        pool.withdraw(40 ether, alice, alice);

        assertEq(pool.cooldownStart(alice), started); // sigue en la ventana
        assertApproxEqAbs(pool.maxWithdraw(alice), 60 ether, 1);
    }

    function test_CanRestartCooldownAfterWindowExpires() public {
        _stake(100 ether);
        _startCooldown();
        vm.warp(block.timestamp + COOLDOWN + WINDOW + 1);

        _startCooldown(); // nuevo ciclo completo
        vm.warp(block.timestamp + COOLDOWN);
        assertTrue(pool.canWithdraw(alice));
    }

    // ─────────────────── Ataque: cooldown con 1 wei ───────────────────

    /// @dev El atacante inicia cooldown con un stake minimo y, al abrirse la
    ///      ventana, mete un stake grande. Sin el reset, podria salir cuando
    ///      quisiera con todo su stake. Con el reset, vuelve a esperar 7 dias.
    function test_DepositResetsCooldown() public {
        _stake(1 ether);
        _startCooldown();
        vm.warp(block.timestamp + COOLDOWN);
        assertTrue(pool.canWithdraw(alice));

        vm.expectEmit(true, false, false, false);
        emit CoveragePool.CooldownReset(alice);
        _stake(500 ether);

        assertEq(pool.cooldownStart(alice), 0);
        assertFalse(pool.canWithdraw(alice));
        assertEq(pool.maxWithdraw(alice), 0);
    }

    /// @dev Griefing: alguien deposita 1 wei a favor de alice para resetearle
    ///      el cooldown y dejarla atrapada. Debe revertir.
    function test_RevertWhen_DepositForAnotherAccount() public {
        address griefer = makeAddr("griefer");
        stakeToken.mint(griefer, 1 ether);

        _stake(100 ether);
        _startCooldown();
        vm.warp(block.timestamp + COOLDOWN);

        vm.startPrank(griefer);
        stakeToken.approve(address(pool), 1);
        vm.expectRevert(CoveragePool.ReceiverMustBeCaller.selector);
        pool.deposit(1, alice);
        vm.stopPrank();

        assertTrue(pool.canWithdraw(alice)); // alice sigue pudiendo salir
    }

    // ─────────────────── Fuzz ───────────────────

    function testFuzz_WithdrawOnlyInsideWindow(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, COOLDOWN + WINDOW * 3);
        _stake(100 ether);
        _startCooldown();
        vm.warp(block.timestamp + elapsed);

        bool insideWindow = elapsed >= COOLDOWN && elapsed <= COOLDOWN + WINDOW;
        assertEq(pool.canWithdraw(alice), insideWindow);
        assertEq(pool.maxWithdraw(alice) > 0, insideWindow);
    }
}