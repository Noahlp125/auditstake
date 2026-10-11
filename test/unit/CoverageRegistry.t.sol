// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CoveragePool} from "../../src/CoveragePool.sol";
import {ClaimManager} from "../../src/ClaimManager.sol";
import {CoverageRegistry} from "../../src/CoverageRegistry.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract CoverageRegistryTest is Test {
    MockERC20 stakeToken;
    MockERC20 premiumToken;
    MockERC20 bondToken;
    CoverageRegistry registry;
    ClaimManager cm;

    address owner = makeAddr("owner");
    address arbiter = makeAddr("arbiter");
    address protocol = makeAddr("protocol"); // contrato cubierto
    address sponsor = makeAddr("sponsor"); // equipo del protocolo
    address auditor = makeAddr("auditor");
    address attacker = makeAddr("attacker");

    function setUp() public {
        stakeToken = new MockERC20("Stake", "STK");
        premiumToken = new MockERC20("Premium", "PRM");
        bondToken = new MockERC20("Bond", "BND");

        // Orden: registry -> ClaimManager(registry) -> conectar
        registry = new CoverageRegistry(owner);
        cm = new ClaimManager(bondToken, 10 ether, 3 days, 14 days, address(registry), arbiter);
        vm.prank(owner);
        registry.setClaimManager(cm);

        stakeToken.mint(auditor, 1_000 ether);
        premiumToken.mint(sponsor, 100_000 ether);
        premiumToken.mint(attacker, 100_000 ether);
        vm.prank(sponsor);
        premiumToken.approve(address(registry), type(uint256).max);
        vm.prank(attacker);
        premiumToken.approve(address(registry), type(uint256).max);
    }

    /// @dev Despliega un pool que confia en `reg` y en `manager`.
    function _deployPool(address reg, address manager) internal returns (CoveragePool) {
        return new CoveragePool(stakeToken, premiumToken, reg, manager, 7 days, 2 days, 5_000, "AuditStake X", "asX");
    }

    function _addPool() internal returns (CoveragePool pool) {
        pool = _deployPool(address(registry), address(cm));
        vm.prank(owner);
        registry.addPool(address(pool), protocol, sponsor);
    }

    function _stake(CoveragePool pool, uint256 amount) internal {
        vm.startPrank(auditor);
        stakeToken.approve(address(pool), amount);
        pool.deposit(amount, auditor);
        vm.stopPrank();
    }

    // ─────────────────── Conexion con el ClaimManager ───────────────────

    function test_RevertWhen_SetClaimManagerTwice() public {
        vm.prank(owner);
        vm.expectRevert(CoverageRegistry.ClaimManagerAlreadySet.selector);
        registry.setClaimManager(cm);
    }

    function test_RevertWhen_ClaimManagerPointsElsewhere() public {
        CoverageRegistry fresh = new CoverageRegistry(owner);
        // cm apunta a `registry`, no a `fresh`
        vm.prank(owner);
        vm.expectRevert(CoverageRegistry.ClaimManagerMismatch.selector);
        fresh.setClaimManager(cm);
    }

    function test_RevertWhen_AddPoolWithoutClaimManager() public {
        CoverageRegistry fresh = new CoverageRegistry(owner);
        CoveragePool pool = _deployPool(address(fresh), address(cm));
        vm.prank(owner);
        vm.expectRevert(CoverageRegistry.ClaimManagerNotSet.selector);
        fresh.addPool(address(pool), protocol, sponsor);
    }

    function test_RevertWhen_NotOwnerSetsClaimManager() public {
        CoverageRegistry fresh = new CoverageRegistry(owner);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        fresh.setClaimManager(cm);
    }

    // ─────────────────── Alta de pools ───────────────────

    function test_AddPoolWiresEverything() public {
        CoveragePool pool = _addPool();

        assertEq(pool.registry(), address(registry));
        assertEq(pool.claimManager(), address(cm));
        assertTrue(cm.isPool(address(pool))); // registrado en el ClaimManager

        assertEq(registry.poolOf(protocol), address(pool));
        (address p, address s, uint64 createdAt) = registry.poolInfo(address(pool));
        assertEq(p, protocol);
        assertEq(s, sponsor);
        assertEq(createdAt, block.timestamp);
        assertEq(registry.poolCount(), 1);
    }

    function test_RevertWhen_NotOwnerAddsPool() public {
        CoveragePool pool = _deployPool(address(registry), address(cm));
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        registry.addPool(address(pool), protocol, sponsor);
    }

    function test_RevertWhen_ProtocolAlreadyCovered() public {
        _addPool();
        CoveragePool other = _deployPool(address(registry), address(cm));
        vm.prank(owner);
        vm.expectRevert(CoverageRegistry.ProtocolAlreadyCovered.selector);
        registry.addPool(address(other), protocol, sponsor);
    }

    function test_RevertWhen_SamePoolAddedTwice() public {
        CoveragePool pool = _addPool();
        vm.prank(owner);
        vm.expectRevert(CoverageRegistry.PoolAlreadyAdded.selector);
        registry.addPool(address(pool), makeAddr("otherProtocol"), sponsor);
    }

    /// @dev Un pool cuyo registry es otro no podria recibir primas de este registry.
    function test_RevertWhen_PoolPointsToAnotherRegistry() public {
        CoveragePool rogue = _deployPool(attacker, address(cm));
        vm.prank(owner);
        vm.expectRevert(CoverageRegistry.PoolMismatch.selector);
        registry.addPool(address(rogue), protocol, sponsor);
    }

    /// @dev Un pool que obedece a otro ClaimManager escaparia de nuestros claims.
    function test_RevertWhen_PoolPointsToAnotherClaimManager() public {
        CoveragePool rogue = _deployPool(address(registry), attacker);
        vm.prank(owner);
        vm.expectRevert(CoverageRegistry.PoolMismatch.selector);
        registry.addPool(address(rogue), protocol, sponsor);
    }

    function test_AddSeveralPools() public {
        _addPool();
        CoveragePool other = _deployPool(address(registry), address(cm));
        vm.prank(owner);
        registry.addPool(address(other), makeAddr("protocolY"), sponsor);

        address[] memory pools = registry.allPools();
        assertEq(pools.length, 2);
        assertTrue(pools[0] != pools[1]);
    }

    // ─────────────────── Primas ───────────────────

    function test_SponsorPaysPremium() public {
        CoveragePool pool = _addPool();
        _stake(pool, 100 ether);

        vm.prank(sponsor);
        registry.payPremium(address(pool), 1_000 ether, 30 days);

        assertEq(premiumToken.balanceOf(address(pool)), 1_000 ether);
        assertEq(premiumToken.balanceOf(address(registry)), 0); // no se queda nada
        assertEq(pool.periodFinish(), block.timestamp + 30 days);

        vm.warp(block.timestamp + 30 days);
        assertApproxEqRel(pool.earned(auditor), 1_000 ether, 1e12);
    }

    function test_RevertWhen_PremiumForUnknownPool() public {
        vm.prank(sponsor);
        vm.expectRevert(CoverageRegistry.UnknownPool.selector);
        registry.payPremium(address(0xBEEF), 1_000 ether, 30 days);
    }

    function test_RevertWhen_PremiumOnEmptyPool() public {
        CoveragePool pool = _addPool();
        vm.prank(sponsor);
        vm.expectRevert(CoverageRegistry.PoolEmpty.selector);
        registry.payPremium(address(pool), 1_000 ether, 30 days);
    }

    function test_RevertWhen_DurationTooShort() public {
        CoveragePool pool = _addPool();
        _stake(pool, 100 ether);
        vm.prank(sponsor);
        vm.expectRevert(CoverageRegistry.InvalidDuration.selector);
        registry.payPremium(address(pool), 1_000 ether, 1 days);
    }

    function test_RevertWhen_DurationTooLong() public {
        CoveragePool pool = _addPool();
        _stake(pool, 100 ether);
        vm.prank(sponsor);
        vm.expectRevert(CoverageRegistry.InvalidDuration.selector);
        registry.payPremium(address(pool), 1_000 ether, 366 days);
    }

    /// @dev Ataque de dilucion: el sponsor paga 1000 en 10 dias. Al dia 5, un atacante
    ///      paga 1 wei con duracion de 365 dias. Si se le permitiera, los 500 pendientes
    ///      se repartirian en un ano en lugar de en 5 dias. Debe revertir.
    function test_RevertWhen_AttackerDilutesRewardRate() public {
        CoveragePool pool = _addPool();
        _stake(pool, 100 ether);
        vm.prank(sponsor);
        registry.payPremium(address(pool), 1_000 ether, 10 days);
        uint256 rateBefore = pool.rewardRate();

        vm.warp(block.timestamp + 5 days);
        vm.prank(attacker);
        vm.expectRevert(CoverageRegistry.NotSponsor.selector);
        registry.payPremium(address(pool), 1, 365 days);

        assertEq(pool.rewardRate(), rateBefore);
    }

    /// @dev Nadie puede saltarse el registry llamando al pool directamente.
    function test_RevertWhen_NotifyPoolDirectly() public {
        CoveragePool pool = _addPool();
        vm.prank(attacker);
        vm.expectRevert(CoveragePool.NotRegistry.selector);
        pool.notifyRewardAmount(1, 365 days);
    }

    // ─────────────────── Propiedad en dos pasos ───────────────────

    function test_OwnershipTransferRequiresAcceptance() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        registry.transferOwnership(newOwner);
        assertEq(registry.owner(), owner); // aun no ha cambiado

        vm.prank(newOwner);
        registry.acceptOwnership();
        assertEq(registry.owner(), newOwner);
    }
}
