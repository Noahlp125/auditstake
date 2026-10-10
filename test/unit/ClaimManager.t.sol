// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CoveragePool} from "../../src/CoveragePool.sol";
import {ClaimManager} from "../../src/ClaimManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract ClaimManagerTest is Test {
    MockERC20 stakeToken;
    MockERC20 premiumToken;
    MockERC20 bondToken;
    CoveragePool pool;
    ClaimManager cm;

    address registry = makeAddr("registry");
    address arbiter = makeAddr("arbiter");
    address auditor = makeAddr("auditor"); // staker del pool
    address reporter = makeAddr("reporter"); // quien reporta el exploit
    address disputer = makeAddr("disputer"); // quien lo disputa
    address victims = makeAddr("victims"); // destino de la compensacion

    uint256 constant BOND = 10 ether;
    uint64 constant DISPUTE_WINDOW = 3 days;
    uint64 constant ARBITRATION_TIMEOUT = 14 days;
    uint256 constant STAKE = 1_000 ether;

    function setUp() public {
        stakeToken = new MockERC20("Stake", "STK");
        premiumToken = new MockERC20("Premium", "PRM");
        bondToken = new MockERC20("Bond", "BND");

        // Orden: primero el ClaimManager, luego el pool que confia en el.
        cm = new ClaimManager(bondToken, BOND, DISPUTE_WINDOW, ARBITRATION_TIMEOUT, registry, arbiter);
        pool = new CoveragePool(
            stakeToken, premiumToken, registry, address(cm), 7 days, 2 days, 5_000, "AuditStake Pool", "asPOOL"
        );
        vm.prank(registry);
        cm.registerPool(address(pool));

        // El auditor respalda el protocolo con 1000 tokens
        stakeToken.mint(auditor, STAKE);
        vm.startPrank(auditor);
        stakeToken.approve(address(pool), type(uint256).max);
        pool.deposit(STAKE, auditor);
        vm.stopPrank();

        // Fondos para fianzas
        bondToken.mint(reporter, 100 ether);
        bondToken.mint(disputer, 100 ether);
        vm.prank(reporter);
        bondToken.approve(address(cm), type(uint256).max);
        vm.prank(disputer);
        bondToken.approve(address(cm), type(uint256).max);
    }

    function _submit(uint256 amount) internal returns (uint256 id) {
        vm.prank(reporter);
        id = cm.submitClaim(address(pool), amount, victims, "ipfs://postmortem");
    }

    function _dispute(uint256 id) internal {
        vm.prank(disputer);
        cm.dispute(id);
    }

    // ─────────────────── Registro ───────────────────

    function test_RevertWhen_NotRegistryRegistersPool() public {
        vm.prank(reporter);
        vm.expectRevert(ClaimManager.NotRegistry.selector);
        cm.registerPool(address(0xBEEF));
    }

    function test_RevertWhen_ClaimOnUnregisteredPool() public {
        vm.prank(reporter);
        vm.expectRevert(ClaimManager.PoolNotRegistered.selector);
        cm.submitClaim(address(0xBEEF), 100 ether, victims, "");
    }

    // ─────────────────── Enviar claim ───────────────────

    function test_SubmitFreezesPoolAndTakesBond() public {
        uint256 id = _submit(100 ether);

        assertEq(id, 1);
        assertTrue(pool.frozen());
        assertEq(cm.activeClaimOf(address(pool)), 1);
        assertEq(bondToken.balanceOf(address(cm)), BOND);

        ClaimManager.Claim memory c = cm.getClaim(id);
        assertEq(c.reporter, reporter);
        assertEq(c.requestedAmount, 100 ether);
        assertEq(c.disputeDeadline, block.timestamp + DISPUTE_WINDOW);
        assertEq(uint8(c.status), uint8(ClaimManager.Status.Pending));
    }

    function test_RevertWhen_SecondClaimOnSamePool() public {
        _submit(100 ether);
        vm.prank(disputer);
        vm.expectRevert(ClaimManager.PoolHasActiveClaim.selector);
        cm.submitClaim(address(pool), 50 ether, victims, "");
    }

    function test_RevertWhen_SubmitZeroAmount() public {
        vm.prank(reporter);
        vm.expectRevert(ClaimManager.ZeroAmount.selector);
        cm.submitClaim(address(pool), 0, victims, "");
    }

    function test_RevertWhen_SubmitWithoutBond() public {
        address broke = makeAddr("broke");
        vm.prank(broke);
        vm.expectRevert(); // sin allowance ni saldo
        cm.submitClaim(address(pool), 100 ether, victims, "");
    }

    // ─────────────────── Camino optimista (sin disputa) ───────────────────

    function test_RevertWhen_FinalizeBeforeDeadline() public {
        uint256 id = _submit(100 ether);
        vm.warp(block.timestamp + DISPUTE_WINDOW); // aun dentro (<=)
        vm.expectRevert(ClaimManager.DisputeWindowOpen.selector);
        cm.finalizeUndisputed(id);
    }

    function test_UndisputedClaimSlashesAndReturnsBond() public {
        uint256 id = _submit(100 ether);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        cm.finalizeUndisputed(id); // cualquiera puede llamarlo

        assertEq(stakeToken.balanceOf(victims), 100 ether);
        assertEq(pool.totalAssets(), STAKE - 100 ether);
        assertEq(bondToken.balanceOf(reporter), 100 ether); // fianza devuelta
        assertFalse(pool.frozen());
        assertEq(cm.activeClaimOf(address(pool)), 0);

        ClaimManager.Claim memory c = cm.getClaim(id);
        assertEq(uint8(c.status), uint8(ClaimManager.Status.Approved));
        assertEq(c.slashedAmount, 100 ether);
    }

    /// @dev Se piden 900 pero el cap del pool es 50% (500): se recorta 500.
    function test_ClaimAboveCapSlashesMaximum() public {
        uint256 id = _submit(900 ether);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        cm.finalizeUndisputed(id);

        assertEq(stakeToken.balanceOf(victims), 500 ether);
        assertEq(cm.getClaim(id).slashedAmount, 500 ether);
    }

    function test_CannotFinalizeTwice() public {
        uint256 id = _submit(100 ether);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        cm.finalizeUndisputed(id);

        vm.expectRevert(abi.encodeWithSelector(ClaimManager.WrongStatus.selector, ClaimManager.Status.Approved));
        cm.finalizeUndisputed(id);
    }

    // ─────────────────── Disputa ───────────────────

    function test_DisputeTakesBondAndBlocksFinalize() public {
        uint256 id = _submit(100 ether);
        _dispute(id);

        assertEq(bondToken.balanceOf(address(cm)), 2 * BOND);
        assertEq(uint8(cm.getClaim(id).status), uint8(ClaimManager.Status.Disputed));
        assertTrue(pool.frozen()); // sigue congelado

        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        vm.expectRevert(abi.encodeWithSelector(ClaimManager.WrongStatus.selector, ClaimManager.Status.Disputed));
        cm.finalizeUndisputed(id);
    }

    function test_RevertWhen_DisputeAfterDeadline() public {
        uint256 id = _submit(100 ether);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        vm.prank(disputer);
        vm.expectRevert(ClaimManager.DisputeWindowClosed.selector);
        cm.dispute(id);
    }

    function test_RevertWhen_DisputeTwice() public {
        uint256 id = _submit(100 ether);
        _dispute(id);
        vm.prank(auditor);
        vm.expectRevert(abi.encodeWithSelector(ClaimManager.WrongStatus.selector, ClaimManager.Status.Disputed));
        cm.dispute(id);
    }

    // ─────────────────── Arbitraje ───────────────────

    function test_RevertWhen_NotArbiterResolves() public {
        uint256 id = _submit(100 ether);
        _dispute(id);
        vm.prank(reporter);
        vm.expectRevert(ClaimManager.NotArbiter.selector);
        cm.resolveDispute(id, true, 100 ether);
    }

    function test_RevertWhen_ResolveUndisputedClaim() public {
        uint256 id = _submit(100 ether);
        vm.prank(arbiter);
        vm.expectRevert(abi.encodeWithSelector(ClaimManager.WrongStatus.selector, ClaimManager.Status.Pending));
        cm.resolveDispute(id, true, 100 ether);
    }

    /// @dev Exploit real: el reportante gana y se lleva la fianza del disputante.
    function test_ArbiterApprovesValidClaim() public {
        uint256 id = _submit(100 ether);
        _dispute(id);

        vm.prank(arbiter);
        cm.resolveDispute(id, true, 80 ether); // el arbitro puede ajustar a la baja

        assertEq(stakeToken.balanceOf(victims), 80 ether);
        assertEq(bondToken.balanceOf(reporter), 100 ether + BOND); // +10 del disputante
        assertEq(bondToken.balanceOf(disputer), 100 ether - BOND); // pierde su fianza
        assertFalse(pool.frozen());
    }

    function test_RevertWhen_ArbiterSlashesMoreThanRequested() public {
        uint256 id = _submit(100 ether);
        _dispute(id);
        vm.prank(arbiter);
        vm.expectRevert(ClaimManager.AmountAboveRequested.selector);
        cm.resolveDispute(id, true, 101 ether);
    }

    /// @dev Ataque: reporte falso para congelar el pool o robar stake.
    ///      Un auditor lo disputa, el arbitro lo rechaza y el atacante pierde la fianza.
    function test_FakeClaimRejectedReporterLosesBond() public {
        uint256 id = _submit(500 ether);
        _dispute(id);

        vm.prank(arbiter);
        cm.resolveDispute(id, false, 0);

        assertEq(stakeToken.balanceOf(victims), 0); // nada recortado
        assertEq(pool.totalAssets(), STAKE);
        assertEq(bondToken.balanceOf(reporter), 100 ether - BOND);
        assertEq(bondToken.balanceOf(disputer), 100 ether + BOND);
        assertFalse(pool.frozen());
        assertEq(uint8(cm.getClaim(id).status), uint8(ClaimManager.Status.Rejected));
    }

    // ─────────────────── Arbitro caido ───────────────────

    function test_RevertWhen_ExpireBeforeTimeout() public {
        uint256 id = _submit(100 ether);
        _dispute(id);
        vm.warp(block.timestamp + ARBITRATION_TIMEOUT);
        vm.expectRevert(ClaimManager.ArbitrationPending.selector);
        cm.expireDispute(id);
    }

    function test_ExpireUnfreezesAndReturnsBothBonds() public {
        uint256 id = _submit(100 ether);
        _dispute(id);
        vm.warp(block.timestamp + ARBITRATION_TIMEOUT + 1);
        cm.expireDispute(id);

        assertFalse(pool.frozen());
        assertEq(bondToken.balanceOf(reporter), 100 ether);
        assertEq(bondToken.balanceOf(disputer), 100 ether);
        assertEq(pool.totalAssets(), STAKE);

        // y el arbitro ya no puede resolverlo tarde
        vm.prank(arbiter);
        vm.expectRevert(abi.encodeWithSelector(ClaimManager.WrongStatus.selector, ClaimManager.Status.Expired));
        cm.resolveDispute(id, true, 100 ether);
    }

    // ─────────────────── Ciclo completo ───────────────────

    function test_NewClaimAfterPreviousResolved() public {
        uint256 first = _submit(100 ether);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        cm.finalizeUndisputed(first);

        uint256 second = _submit(50 ether);
        assertEq(second, 2);
        assertTrue(pool.frozen());
    }

    /// @dev Cualquier ruta de resolucion deja el pool descongelado y sin claim activo.
    function testFuzz_EveryResolutionUnfreezes(uint8 path, uint256 amount) public {
        amount = bound(amount, 1, STAKE);
        uint256 id = _submit(amount);
        path = uint8(bound(path, 0, 3));

        if (path == 0) {
            vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
            cm.finalizeUndisputed(id);
        } else {
            _dispute(id);
            if (path == 1) {
                vm.prank(arbiter);
                cm.resolveDispute(id, true, amount);
            } else if (path == 2) {
                vm.prank(arbiter);
                cm.resolveDispute(id, false, 0);
            } else {
                vm.warp(block.timestamp + ARBITRATION_TIMEOUT + 1);
                cm.expireDispute(id);
            }
        }

        assertFalse(pool.frozen());
        assertEq(cm.activeClaimOf(address(pool)), 0);
        assertEq(bondToken.balanceOf(address(cm)), 0); // nunca se quedan fianzas atrapadas
        assertLe(stakeToken.balanceOf(victims), STAKE / 2); // nunca mas del cap
    }
}
