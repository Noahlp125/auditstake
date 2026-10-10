// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CoveragePool} from "../../src/CoveragePool.sol";
import {ClaimManager} from "../../src/ClaimManager.sol";
import {CoverageRegistry} from "../../src/CoverageRegistry.sol";
import {PoolFactory} from "../../src/PoolFactory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice La historia completa del protocolo, de principio a fin.
///         Es el test que conviene ensenar en la defensa.
contract FullFlowTest is Test {
    MockERC20 stakeToken;
    MockERC20 premiumToken;
    MockERC20 bondToken;
    PoolFactory factory;
    CoverageRegistry registry;
    ClaimManager cm;
    CoveragePool pool;

    address owner = makeAddr("owner");
    address arbiter = makeAddr("arbiter");
    address protocol = makeAddr("protocolX");
    address sponsor = makeAddr("sponsorX");
    address alice = makeAddr("alice"); // auditora senior: 300
    address bob = makeAddr("bob"); // auditor: 100
    address whitehat = makeAddr("whitehat");
    address victimsFund = makeAddr("victimsFund");

    function setUp() public {
        stakeToken = new MockERC20("Stake", "STK");
        premiumToken = new MockERC20("Premium", "PRM");
        bondToken = new MockERC20("Bond", "BND");

        factory = new PoolFactory();
        registry = new CoverageRegistry(owner, factory);
        cm = new ClaimManager(bondToken, 10 ether, 3 days, 14 days, address(registry), arbiter);
        vm.startPrank(owner);
        registry.setClaimManager(cm);
        pool = CoveragePool(
            registry.createPool(protocol, sponsor, stakeToken, premiumToken, 7 days, 2 days, 5_000, "AuditStake X", "asX")
        );
        vm.stopPrank();

        stakeToken.mint(alice, 300 ether);
        stakeToken.mint(bob, 100 ether);
        premiumToken.mint(sponsor, 10_000 ether);
        bondToken.mint(whitehat, 10 ether);
    }

    function test_FullLifecycle() public {
        // 1. Los auditores respaldan el protocolo
        vm.startPrank(alice);
        stakeToken.approve(address(pool), 300 ether);
        pool.deposit(300 ether, alice);
        vm.stopPrank();
        vm.startPrank(bob);
        stakeToken.approve(address(pool), 100 ether);
        pool.deposit(100 ether, bob);
        vm.stopPrank();

        // 2. El protocolo paga 4000 de prima por 40 dias de cobertura
        vm.startPrank(sponsor);
        premiumToken.approve(address(registry), 4_000 ether);
        registry.payPremium(address(pool), 4_000 ether, 40 days);
        vm.stopPrank();

        // 3. Pasan 20 dias tranquilos: se han repartido 2000 (75% / 25%)
        vm.warp(block.timestamp + 20 days);
        assertApproxEqRel(pool.earned(alice), 1_500 ether, 1e12);
        assertApproxEqRel(pool.earned(bob), 500 ether, 1e12);

        // 4. Un whitehat detecta un exploit y lo reporta: pide 100 para las victimas
        vm.startPrank(whitehat);
        bondToken.approve(address(cm), 10 ether);
        uint256 claimId = cm.submitClaim(address(pool), 100 ether, victimsFund, "ipfs://postmortem-x");
        vm.stopPrank();
        assertTrue(pool.frozen());

        // 5. Bob intenta huir: no puede, el pool esta congelado
        vm.prank(bob);
        pool.startCooldown();
        assertEq(pool.maxWithdraw(bob), 0);

        // 6. Nadie disputa (el exploit es real). Pasan 3 dias y se ejecuta.
        vm.warp(block.timestamp + 3 days + 1);
        cm.finalizeUndisputed(claimId);

        assertEq(stakeToken.balanceOf(victimsFund), 100 ether);
        assertEq(bondToken.balanceOf(whitehat), 10 ether); // fianza devuelta
        assertFalse(pool.frozen());

        // 7. Las perdidas se reparten en proporcion: 400 -> 300
        assertApproxEqAbs(pool.convertToAssets(pool.balanceOf(alice)), 225 ether, 1e6);
        assertApproxEqAbs(pool.convertToAssets(pool.balanceOf(bob)), 75 ether, 1e6);

        // 8. La prima ya ganada sigue siendo suya: alice cobra
        vm.prank(alice);
        uint256 aliceReward = pool.claimRewards();
        assertGt(aliceReward, 1_500 ether); // 20 dias + los 3 del claim

        // 9. Bob vuelve a iniciar cooldown, espera y sale con lo que le queda
        vm.prank(bob);
        pool.startCooldown();
        vm.warp(block.timestamp + 7 days);
        uint256 bobShares = pool.balanceOf(bob);
        vm.prank(bob);
        uint256 bobOut = pool.redeem(bobShares, bob, bob);
        assertApproxEqAbs(bobOut, 75 ether, 1e6);

        // 10. Conservacion: todo el stake inicial esta en algun sitio
        uint256 inPool = stakeToken.balanceOf(address(pool));
        assertApproxEqAbs(inPool + bobOut + 100 ether, 400 ether, 2);
    }
}
