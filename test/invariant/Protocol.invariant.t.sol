// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CoveragePool} from "../../src/CoveragePool.sol";
import {ClaimManager} from "../../src/ClaimManager.sol";
import {CoverageRegistry} from "../../src/CoverageRegistry.sol";
import {PoolFactory} from "../../src/PoolFactory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ProtocolHandler} from "./handlers/ProtocolHandler.sol";

/// @notice Propiedades que deben cumplirse SIEMPRE, despues de cualquier secuencia
///         de acciones: depositos, retiradas, primas, claims, disputas y saltos de tiempo.
contract ProtocolInvariantTest is StdInvariant, Test {
    MockERC20 stakeToken;
    MockERC20 premiumToken;
    MockERC20 bondToken;
    PoolFactory factory;
    CoverageRegistry registry;
    ClaimManager cm;
    CoveragePool pool;
    ProtocolHandler handler;

    address owner = makeAddr("owner");
    address arbiter = makeAddr("arbiter");
    address sponsor = makeAddr("sponsor");

    uint16 constant MAX_SLASH_BPS = 5_000;

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
            registry.createPool(
                makeAddr("protocol"), sponsor, stakeToken, premiumToken, 7 days, 2 days, MAX_SLASH_BPS, "AS", "AS"
            )
        );
        vm.stopPrank();

        handler = new ProtocolHandler(pool, cm, registry, stakeToken, premiumToken, bondToken, sponsor, arbiter);

        // El fuzzer SOLO llama al handler, nunca directamente a los contratos.
        targetContract(address(handler));
    }

    // ─────────────────── Stake ───────────────────

    /// @notice Conservacion: el stake del pool es exactamente lo que entro menos lo que salio.
    ///         Si algun camino creara o destruyera tokens, esto fallaria.
    function invariant_StakeConservation() public view {
        assertEq(
            stakeToken.balanceOf(address(pool)),
            handler.ghost_deposited() - handler.ghost_withdrawn() - handler.ghost_slashed()
        );
    }

    /// @notice Lo que valen todas las shares juntas nunca supera los activos del pool.
    function invariant_SharesBackedByAssets() public view {
        assertLe(pool.convertToAssets(pool.totalSupply()), pool.totalAssets());
    }

    /// @notice Lo que ha llegado a las victimas es exactamente lo recortado.
    function invariant_SlashedGoesToVictims() public view {
        assertEq(stakeToken.balanceOf(handler.victims()), handler.ghost_slashed());
    }

    // ─────────────────── Slashing ───────────────────

    /// @notice Nunca se recorta mas del cap sobre la foto tomada al congelar.
    function invariant_SlashNeverExceedsCap() public view {
        uint256 cap = Math.mulDiv(pool.frozenAssetsSnapshot(), MAX_SLASH_BPS, 10_000);
        assertLe(pool.slashedDuringFreeze(), cap);
    }

    /// @notice El pool esta congelado si y solo si hay un claim abierto.
    ///         Detecta pools atascados (congelados sin claim) o claims sin congelar.
    function invariant_FrozenIffActiveClaim() public view {
        assertEq(pool.frozen(), cm.activeClaimOf(address(pool)) != 0);
    }

    /// @notice Nadie ha conseguido retirar con el pool congelado.
    function invariant_NoWithdrawWhileFrozen() public view {
        assertEq(handler.ghost_withdrawWhileFrozen(), 0);
    }

    // ─────────────────── Recompensas ───────────────────

    /// @notice Solvencia de primas: el pool siempre tiene tokens para pagar
    ///         todo lo que debe a los stakers.
    function invariant_RewardsAreSolvent() public view {
        assertLe(handler.sumEarned(), premiumToken.balanceOf(address(pool)));
    }

    /// @notice Conservacion de primas: lo que entro = lo que hay + lo que se cobro.
    function invariant_PremiumConservation() public view {
        assertEq(
            handler.ghost_premiumPaid(), premiumToken.balanceOf(address(pool)) + handler.ghost_rewardsClaimed()
        );
    }

    /// @notice El acumulador de recompensas nunca retrocede.
    function invariant_RewardPerShareMonotonic() public view {
        assertFalse(handler.ghost_rewardPerShareDecreased());
    }

    // ─────────────────── Fianzas ───────────────────

    /// @notice El ClaimManager guarda exactamente las fianzas de los claims vivos:
    ///         1 por claim pendiente, 2 por claim disputado. Ni una mas, ni una menos.
    function invariant_BondsAccounting() public view {
        uint256 expected;
        uint256 n = cm.claimCount();
        for (uint256 id = 1; id <= n; id++) {
            ClaimManager.Status s = cm.getClaim(id).status;
            if (s == ClaimManager.Status.Pending) expected += 1;
            else if (s == ClaimManager.Status.Disputed) expected += 2;
        }
        assertEq(bondToken.balanceOf(address(cm)), expected * cm.bondAmount());
    }

    /// @notice Al final de cada secuencia, cuantas acciones se ejecutaron de verdad.
    function afterInvariant() external view {
        console.log("deposit        ", handler.calls("deposit"));
        console.log("startCooldown  ", handler.calls("startCooldown"));
        console.log("redeem         ", handler.calls("redeem"));
        console.log("attackFrozen   ", handler.calls("attackFrozen"));
        console.log("claimRewards   ", handler.calls("claimRewards"));
        console.log("payPremium     ", handler.calls("payPremium"));
        console.log("submitClaim    ", handler.calls("submitClaim"));
        console.log("dispute        ", handler.calls("dispute"));
        console.log("finalize       ", handler.calls("finalize"));
        console.log("resolve        ", handler.calls("resolve"));
        console.log("expire         ", handler.calls("expire"));
        console.log("warp           ", handler.calls("warp"));
        console.log("total slashed  ", handler.ghost_slashed());
    }
}
