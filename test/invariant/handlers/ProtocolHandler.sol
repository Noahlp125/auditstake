// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CoveragePool} from "../../../src/CoveragePool.sol";
import {ClaimManager} from "../../../src/ClaimManager.sol";
import {CoverageRegistry} from "../../../src/CoverageRegistry.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

/// @notice El "Handler" es el intermediario entre el fuzzer y el protocolo.
///         El fuzzer llama a sus funciones en orden aleatorio con argumentos aleatorios;
///         el handler los acota a valores con sentido y ejecuta la accion real.
///         Ademas lleva "variables fantasma" (ghost) con la contabilidad que esperamos,
///         para que los invariantes puedan compararla con el estado real.
contract ProtocolHandler is Test {
    CoveragePool public pool;
    ClaimManager public cm;
    CoverageRegistry public registry;
    MockERC20 public stakeToken;
    MockERC20 public premiumToken;
    MockERC20 public bondToken;

    address public sponsor;
    address public arbiter;
    address public victims = makeAddr("victims");

    address[] public actors;
    address internal currentActor;

    // ─────────────────── Variables fantasma ───────────────────
    uint256 public ghost_deposited; // stake que ha entrado al pool
    uint256 public ghost_withdrawn; // stake que ha salido por retiradas
    uint256 public ghost_slashed; // stake que ha salido por slashing
    uint256 public ghost_premiumPaid; // prima total recibida por el pool
    uint256 public ghost_rewardsClaimed; // prima total cobrada por los stakers
    uint256 public ghost_withdrawWhileFrozen; // retiradas con el pool congelado (debe ser 0)
    uint256 public ghost_lastRewardPerShare; // para comprobar que nunca baja
    bool public ghost_rewardPerShareDecreased;

    uint256[] public openClaims; // claims que aun pueden avanzar

    // Acciones que se EJECUTARON de verdad (sin contar las que salieron antes por no
    // tener sentido). Sirve para comprobar que el fuzzer explora todo el protocolo.
    mapping(bytes32 => uint256) public calls;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @dev Tras cada accion, comprobamos que el acumulador de recompensas no ha bajado.
    modifier checkpoint() {
        _;
        _checkRewardPerShare();
    }

    constructor(
        CoveragePool pool_,
        ClaimManager cm_,
        CoverageRegistry registry_,
        MockERC20 stakeToken_,
        MockERC20 premiumToken_,
        MockERC20 bondToken_,
        address sponsor_,
        address arbiter_
    ) {
        pool = pool_;
        cm = cm_;
        registry = registry_;
        stakeToken = stakeToken_;
        premiumToken = premiumToken_;
        bondToken = bondToken_;
        sponsor = sponsor_;
        arbiter = arbiter_;

        for (uint256 i; i < 4; i++) {
            address a = makeAddr(string(abi.encodePacked("actor", vm.toString(i))));
            actors.push(a);
            vm.startPrank(a);
            stakeToken.approve(address(pool), type(uint256).max);
            bondToken.approve(address(cm), type(uint256).max);
            vm.stopPrank();
        }
        vm.prank(sponsor);
        premiumToken.approve(address(registry), type(uint256).max);
    }

    // ═══════════════════════════ Stakers ═══════════════════════════

    function deposit(uint256 actorSeed, uint256 amount) external useActor(actorSeed) checkpoint {
        if (pool.frozen()) return;
        amount = bound(amount, 1e6, 1_000 ether);
        stakeToken.mint(currentActor, amount);
        pool.deposit(amount, currentActor);
        ghost_deposited += amount;
        calls["deposit"]++;
    }

    function startCooldown(uint256 actorSeed) external useActor(actorSeed) checkpoint {
        if (pool.balanceOf(currentActor) == 0) return;
        pool.startCooldown();
        calls["startCooldown"]++;
    }

    /// @dev Retirar exige cooldown + esperar 7 dias. Con saltos de tiempo aleatorios casi
    ///      nunca se acierta la ventana, asi que aqui se hace el ciclo completo de golpe.
    function redeem(uint256 actorSeed, uint256 shares) external useActor(actorSeed) checkpoint {
        if (pool.balanceOf(currentActor) == 0 || pool.frozen()) return;
        if (!pool.canWithdraw(currentActor)) {
            pool.startCooldown();
            vm.warp(block.timestamp + pool.cooldownPeriod());
        }
        uint256 maxShares = pool.maxRedeem(currentActor);
        if (maxShares == 0) return;
        shares = bound(shares, 1, maxShares);
        ghost_withdrawn += pool.redeem(shares, currentActor, currentActor);
        calls["redeem"]++;
    }

    /// @dev ATAQUE: intentar retirar con el pool congelado, con el cooldown ya cumplido.
    ///      Si alguna vez funciona, el invariante NoWithdrawWhileFrozen lo detecta.
    function attackWithdrawWhileFrozen(uint256 actorSeed) external useActor(actorSeed) checkpoint {
        if (!pool.frozen()) return;
        uint256 shares = pool.balanceOf(currentActor);
        if (shares == 0) return;
        try pool.redeem(shares, currentActor, currentActor) returns (uint256 assets) {
            ghost_withdrawn += assets;
            ghost_withdrawWhileFrozen++;
        } catch {}
        calls["attackFrozen"]++;
    }

    function claimRewards(uint256 actorSeed) external useActor(actorSeed) checkpoint {
        ghost_rewardsClaimed += pool.claimRewards();
        calls["claimRewards"]++;
    }

    // ═══════════════════════════ Sponsor ═══════════════════════════

    function payPremium(uint256 amount, uint256 duration) external checkpoint {
        if (pool.totalSupply() == 0) return;
        amount = bound(amount, 1 ether, 10_000 ether);
        duration = bound(duration, registry.MIN_PREMIUM_DURATION(), registry.MAX_PREMIUM_DURATION());
        premiumToken.mint(sponsor, amount);
        vm.prank(sponsor);
        registry.payPremium(address(pool), amount, duration);
        ghost_premiumPaid += amount;
        calls["payPremium"]++;
    }

    // ═══════════════════════════ Claims ═══════════════════════════

    function submitClaim(uint256 actorSeed, uint256 amount) external useActor(actorSeed) checkpoint {
        if (pool.frozen() || pool.totalAssets() == 0) return;
        amount = bound(amount, 1, pool.totalAssets());
        bondToken.mint(currentActor, cm.bondAmount());
        uint256 id = cm.submitClaim(address(pool), amount, victims, "ipfs://x");
        openClaims.push(id);
        calls["submitClaim"]++;
    }

    function dispute(uint256 actorSeed, uint256 claimSeed) external useActor(actorSeed) checkpoint {
        if (openClaims.length == 0) return;
        uint256 id = openClaims[bound(claimSeed, 0, openClaims.length - 1)];
        ClaimManager.Claim memory c = cm.getClaim(id);
        if (c.status != ClaimManager.Status.Pending || block.timestamp > c.disputeDeadline) return;
        bondToken.mint(currentActor, cm.bondAmount());
        cm.dispute(id);
        calls["dispute"]++;
    }

    function finalizeUndisputed(uint256 claimSeed) external checkpoint {
        if (openClaims.length == 0) return;
        uint256 idx = bound(claimSeed, 0, openClaims.length - 1);
        uint256 id = openClaims[idx];
        ClaimManager.Claim memory c = cm.getClaim(id);
        if (c.status != ClaimManager.Status.Pending || block.timestamp <= c.disputeDeadline) return;
        cm.finalizeUndisputed(id);
        ghost_slashed += cm.getClaim(id).slashedAmount;
        _removeClaim(idx);
        calls["finalize"]++;
    }

    function resolveDispute(uint256 claimSeed, bool valid, uint256 amount) external checkpoint {
        if (openClaims.length == 0) return;
        uint256 idx = bound(claimSeed, 0, openClaims.length - 1);
        uint256 id = openClaims[idx];
        ClaimManager.Claim memory c = cm.getClaim(id);
        if (c.status != ClaimManager.Status.Disputed) return;
        amount = bound(amount, 1, c.requestedAmount);
        vm.prank(arbiter);
        cm.resolveDispute(id, valid, amount);
        ghost_slashed += cm.getClaim(id).slashedAmount;
        _removeClaim(idx);
        calls["resolve"]++;
    }

    function expireDispute(uint256 claimSeed) external checkpoint {
        if (openClaims.length == 0) return;
        uint256 idx = bound(claimSeed, 0, openClaims.length - 1);
        uint256 id = openClaims[idx];
        ClaimManager.Claim memory c = cm.getClaim(id);
        if (c.status != ClaimManager.Status.Disputed || block.timestamp <= c.arbitrationDeadline) return;
        cm.expireDispute(id);
        _removeClaim(idx);
        calls["expire"]++;
    }

    // ═══════════════════════════ Tiempo ═══════════════════════════

    function warp(uint256 seconds_) external checkpoint {
        vm.warp(block.timestamp + bound(seconds_, 1 hours, 10 days));
        calls["warp"]++;
    }

    // ═══════════════════════════ Ayudas ═══════════════════════════

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function sumEarned() external view returns (uint256 total) {
        for (uint256 i; i < actors.length; i++) {
            total += pool.earned(actors[i]);
        }
    }

    function _removeClaim(uint256 idx) internal {
        openClaims[idx] = openClaims[openClaims.length - 1];
        openClaims.pop();
    }

    function _checkRewardPerShare() internal {
        uint256 current = pool.rewardPerShareStored();
        if (current < ghost_lastRewardPerShare) ghost_rewardPerShareDecreased = true;
        ghost_lastRewardPerShare = current;
    }
}
