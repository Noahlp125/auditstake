// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {CoveragePool} from "./CoveragePool.sol";
import {ClaimManager} from "./ClaimManager.sol";

/// @title CoverageRegistry
/// @notice Punto de entrada del protocolo:
///         - Da de alta un CoveragePool por protocolo cubierto y lo registra en el ClaimManager.
///         - Recibe las primas de cada protocolo y las reparte a su pool.
/// @dev Los pools se despliegan FUERA del registry (desde el script) y luego se dan de alta
///      con addPool(). Antes los creaba una PoolFactory, pero su despliegue necesitaba mas
///      gas que el maximo por transaccion de la red (EIP-7825: 2^24 ≈ 16,7M) en Sepolia.
/// @dev Ownable2Step: transferir la propiedad exige que el nuevo owner la acepte,
///      asi un error al teclear la direccion no deja el registry sin dueno.
contract CoverageRegistry is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────── Tipos ───────────────────────────
    struct PoolInfo {
        address protocol; // contrato cubierto
        address sponsor; // quien paga la prima (el equipo del protocolo)
        uint64 createdAt;
    }

    // ─────────────────────────── Errores ───────────────────────────
    error ZeroAddress();
    error ClaimManagerAlreadySet();
    error ClaimManagerNotSet();
    error ClaimManagerMismatch();
    error PoolMismatch();
    error PoolAlreadyAdded();
    error ProtocolAlreadyCovered();
    error UnknownPool();
    error NotSponsor();
    error InvalidDuration();
    error PoolEmpty();

    // ─────────────────────────── Eventos ───────────────────────────
    event ClaimManagerSet(address indexed claimManager);
    event PoolAdded(address indexed pool, address indexed protocol, address indexed sponsor);
    event PremiumPaid(address indexed pool, address indexed payer, uint256 amount, uint256 duration);

    // ───────────────────────── Configuración ─────────────────────────
    uint256 public constant MIN_PREMIUM_DURATION = 7 days;
    uint256 public constant MAX_PREMIUM_DURATION = 365 days;

    ClaimManager public claimManager;

    // ─────────────────────────── Estado ───────────────────────────
    mapping(address => PoolInfo) public poolInfo; // pool => info
    mapping(address => address) public poolOf; // protocolo => pool
    address[] internal _pools;

    constructor(address owner_) Ownable(owner_) {}

    // ═══════════════════════════ Configuracion inicial ═══════════════════════════

    /// @notice Conecta el ClaimManager. Solo se puede hacer UNA vez.
    /// @dev Dependencia circular: el ClaimManager guarda el registry como immutable,
    ///      asi que hay que desplegar primero el registry, luego el ClaimManager
    ///      apuntando a el, y por ultimo conectarlos aqui. Se comprueba que el
    ///      ClaimManager apunta de vuelta a este registry para no conectar uno ajeno.
    function setClaimManager(ClaimManager claimManager_) external onlyOwner {
        if (address(claimManager) != address(0)) revert ClaimManagerAlreadySet();
        if (address(claimManager_) == address(0)) revert ZeroAddress();
        if (claimManager_.registry() != address(this)) revert ClaimManagerMismatch();
        claimManager = claimManager_;
        emit ClaimManagerSet(address(claimManager_));
    }

    // ═══════════════════════════ Pools ═══════════════════════════

    /// @notice Da de alta el pool de cobertura de `protocol`.
    /// @param pool Un CoveragePool ya desplegado que apunte a ESTE registry y a NUESTRO ClaimManager.
    /// @param sponsor Direccion del equipo del protocolo: la unica que podra pagar primas.
    /// @dev Se comprueba que el pool confia en este registry y en nuestro ClaimManager (son
    ///      immutables del pool). Un pool que apuntara a otros contratos no podria recibir
    ///      primas ni ser congelado, y se rechaza.
    function addPool(address pool, address protocol, address sponsor) external onlyOwner {
        if (address(claimManager) == address(0)) revert ClaimManagerNotSet();
        if (pool == address(0) || protocol == address(0) || sponsor == address(0)) revert ZeroAddress();
        if (poolOf[protocol] != address(0)) revert ProtocolAlreadyCovered();
        if (poolInfo[pool].protocol != address(0)) revert PoolAlreadyAdded();
        if (CoveragePool(pool).registry() != address(this) || CoveragePool(pool).claimManager() != address(claimManager))
        {
            revert PoolMismatch();
        }

        poolInfo[pool] = PoolInfo({protocol: protocol, sponsor: sponsor, createdAt: uint64(block.timestamp)});
        poolOf[protocol] = pool;
        _pools.push(pool);

        claimManager.registerPool(pool);
        emit PoolAdded(pool, protocol, sponsor);
    }

    // ═══════════════════════════ Primas ═══════════════════════════

    /// @notice El sponsor paga la prima, que se reparte a los stakers durante `duration`.
    /// @dev Tres protecciones:
    ///      1. Solo el sponsor: si cualquiera pudiera llamar, un atacante pagaria 1 wei
    ///         con duration = 365 dias y estiraria la prima pendiente sobre un ano entero
    ///         (rewardRate se recalcula como (nuevo + pendiente) / duration). Griefing.
    ///      2. Duracion acotada [7 dias, 365 dias] como defensa adicional.
    ///      3. El pool debe tener stake: la prima que corre con el pool vacio no es de
    ///         nadie y se quedaria atrapada en el contrato.
    function payPremium(address pool, uint256 amount, uint256 duration) external nonReentrant {
        PoolInfo memory info = poolInfo[pool];
        if (info.protocol == address(0)) revert UnknownPool();
        if (msg.sender != info.sponsor) revert NotSponsor();
        if (duration < MIN_PREMIUM_DURATION || duration > MAX_PREMIUM_DURATION) revert InvalidDuration();
        if (CoveragePool(pool).totalSupply() == 0) revert PoolEmpty();

        IERC20 premiumToken = CoveragePool(pool).rewardToken();

        // Se mide lo recibido (tokens con comision) y se pasa exactamente eso al pool.
        uint256 balBefore = premiumToken.balanceOf(address(this));
        premiumToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = premiumToken.balanceOf(address(this)) - balBefore;

        premiumToken.forceApprove(pool, received);
        CoveragePool(pool).notifyRewardAmount(received, duration);

        emit PremiumPaid(pool, msg.sender, received, duration);
    }

    // ═══════════════════════════ Vistas ═══════════════════════════

    function poolCount() external view returns (uint256) {
        return _pools.length;
    }

    function allPools() external view returns (address[] memory) {
        return _pools;
    }
}
