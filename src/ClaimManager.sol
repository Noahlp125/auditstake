// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ICoveragePool} from "./interfaces/ICoveragePool.sol";

/// @title ClaimManager
/// @notice Gestiona los reportes de exploit con un modelo OPTIMISTA:
///         1. Alguien reporta un exploit depositando una fianza (bond). El pool se congela.
///         2. Se abre una ventana de disputa. Si nadie disputa, el claim se aprueba solo.
///         3. Si alguien disputa (depositando otra fianza igual), decide el arbitro.
///         4. Quien pierde la disputa pierde su fianza, que va al ganador.
/// @dev Reportar en falso sale caro (pierdes la fianza si te disputan) y reportar un
///      exploit real sale gratis (recuperas la fianza). Disputar en falso tambien cuesta.
contract ClaimManager is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────── Tipos ───────────────────────────
    enum Status {
        None,
        Pending, // ventana de disputa abierta
        Disputed, // esperando al arbitro
        Approved, // slash ejecutado
        Rejected, // claim falso: sin slash
        Expired // el arbitro no respondio a tiempo

    }

    struct Claim {
        address pool;
        address reporter;
        address disputer;
        address recipient; // quien recibe lo recortado (p.ej. contrato de compensacion)
        uint256 requestedAmount;
        uint256 slashedAmount;
        uint64 disputeDeadline;
        uint64 arbitrationDeadline;
        Status status;
        string evidenceURI; // enlace al post-mortem, tx del exploit, etc.
    }

    // ─────────────────────────── Errores ───────────────────────────
    error ZeroAddress();
    error ZeroAmount();
    error InvalidDuration();
    error NotRegistry();
    error NotArbiter();
    error PoolNotRegistered();
    error PoolHasActiveClaim();
    error WrongStatus(Status current);
    error DisputeWindowOpen();
    error DisputeWindowClosed();
    error ArbitrationPending();
    error AmountAboveRequested();

    // ─────────────────────────── Eventos ───────────────────────────
    event PoolRegistered(address indexed pool);
    event ClaimSubmitted(
        uint256 indexed claimId, address indexed pool, address indexed reporter, uint256 amount, string evidenceURI
    );
    event ClaimDisputed(uint256 indexed claimId, address indexed disputer);
    event ClaimApproved(uint256 indexed claimId, uint256 slashedAmount);
    event ClaimRejected(uint256 indexed claimId);
    event ClaimExpired(uint256 indexed claimId);

    // ───────────────────────── Configuración ─────────────────────────
    uint256 internal constant BPS = 10_000;

    IERC20 public immutable bondToken;
    uint256 public immutable bondAmount;
    uint64 public immutable disputeWindow;
    uint64 public immutable arbitrationTimeout;
    address public immutable registry;
    address public immutable arbiter;

    // ─────────────────────────── Estado ───────────────────────────
    mapping(address => bool) public isPool;
    mapping(address => uint256) public activeClaimOf; // pool => claimId (0 = ninguno)
    mapping(uint256 => Claim) internal _claims;
    uint256 public claimCount;

    modifier onlyRegistry() {
        if (msg.sender != registry) revert NotRegistry();
        _;
    }

    modifier onlyArbiter() {
        if (msg.sender != arbiter) revert NotArbiter();
        _;
    }

    constructor(
        IERC20 bondToken_,
        uint256 bondAmount_,
        uint64 disputeWindow_,
        uint64 arbitrationTimeout_,
        address registry_,
        address arbiter_
    ) {
        if (address(bondToken_) == address(0) || registry_ == address(0) || arbiter_ == address(0)) {
            revert ZeroAddress();
        }
        if (bondAmount_ == 0) revert ZeroAmount();
        if (disputeWindow_ == 0 || arbitrationTimeout_ == 0) revert InvalidDuration();

        bondToken = bondToken_;
        bondAmount = bondAmount_;
        disputeWindow = disputeWindow_;
        arbitrationTimeout = arbitrationTimeout_;
        registry = registry_;
        arbiter = arbiter_;
    }

    // ═══════════════════════════ Registro ═══════════════════════════

    /// @notice Solo se aceptan claims sobre pools dados de alta por el registry.
    /// @dev Sin esta lista, un atacante podria pasar como "pool" un contrato propio
    ///      cuyo freeze() o slash() hiciera reentrada en este contrato.
    function registerPool(address pool) external onlyRegistry {
        if (pool == address(0)) revert ZeroAddress();
        isPool[pool] = true;
        emit PoolRegistered(pool);
    }

    // ═══════════════════════════ Flujo del claim ═══════════════════════════

    /// @notice Reporta un exploit en el protocolo que cubre `pool`.
    /// @param requestedAmount Cuanto stake se pide recortar para compensar.
    /// @param recipient Donde ira lo recortado.
    /// @param evidenceURI Pruebas del exploit (tx hash, post-mortem en IPFS...).
    function submitClaim(address pool, uint256 requestedAmount, address recipient, string calldata evidenceURI)
        external
        nonReentrant
        returns (uint256 claimId)
    {
        if (!isPool[pool]) revert PoolNotRegistered();
        if (activeClaimOf[pool] != 0) revert PoolHasActiveClaim();
        if (requestedAmount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        claimId = ++claimCount; // empieza en 1: el 0 significa "sin claim"
        Claim storage c = _claims[claimId];
        c.pool = pool;
        c.reporter = msg.sender;
        c.recipient = recipient;
        c.requestedAmount = requestedAmount;
        c.disputeDeadline = uint64(block.timestamp) + disputeWindow;
        c.status = Status.Pending;
        c.evidenceURI = evidenceURI;
        activeClaimOf[pool] = claimId;

        bondToken.safeTransferFrom(msg.sender, address(this), bondAmount);
        ICoveragePool(pool).freeze();

        emit ClaimSubmitted(claimId, pool, msg.sender, requestedAmount, evidenceURI);
    }

    /// @notice Disputa un claim que crees falso, depositando una fianza igual.
    function dispute(uint256 claimId) external nonReentrant {
        Claim storage c = _claims[claimId];
        if (c.status != Status.Pending) revert WrongStatus(c.status);
        if (block.timestamp > c.disputeDeadline) revert DisputeWindowClosed();

        c.status = Status.Disputed;
        c.disputer = msg.sender;
        c.arbitrationDeadline = uint64(block.timestamp) + arbitrationTimeout;

        bondToken.safeTransferFrom(msg.sender, address(this), bondAmount);
        emit ClaimDisputed(claimId, msg.sender);
    }

    /// @notice Si nadie disputo a tiempo, cualquiera puede ejecutar el claim.
    /// @dev Esto es lo "optimista": el silencio equivale a aprobacion. Por eso los
    ///      auditores (o un bot vigilante) deben revisar cada claim que se abre.
    function finalizeUndisputed(uint256 claimId) external nonReentrant {
        Claim storage c = _claims[claimId];
        if (c.status != Status.Pending) revert WrongStatus(c.status);
        if (block.timestamp <= c.disputeDeadline) revert DisputeWindowOpen();

        _approve(claimId, c, c.requestedAmount);
        bondToken.safeTransfer(c.reporter, bondAmount); // recupera su fianza
    }

    /// @notice El arbitro decide un claim disputado.
    /// @param valid True si el exploit es real.
    /// @param amount Cuanto recortar si es valido (puede ser menos de lo pedido).
    function resolveDispute(uint256 claimId, bool valid, uint256 amount) external nonReentrant onlyArbiter {
        Claim storage c = _claims[claimId];
        if (c.status != Status.Disputed) revert WrongStatus(c.status);

        if (valid) {
            if (amount == 0) revert ZeroAmount();
            if (amount > c.requestedAmount) revert AmountAboveRequested();
            _approve(claimId, c, amount);
            bondToken.safeTransfer(c.reporter, 2 * bondAmount); // su fianza + la del disputante
        } else {
            c.status = Status.Rejected;
            _close(c);
            bondToken.safeTransfer(c.disputer, 2 * bondAmount); // su fianza + la del reportante
            emit ClaimRejected(claimId);
        }
    }

    /// @notice Salida de emergencia si el arbitro no responde: sin ella, un arbitro
    ///         caido dejaria el pool congelado para siempre. Se devuelven ambas fianzas.
    function expireDispute(uint256 claimId) external nonReentrant {
        Claim storage c = _claims[claimId];
        if (c.status != Status.Disputed) revert WrongStatus(c.status);
        if (block.timestamp <= c.arbitrationDeadline) revert ArbitrationPending();

        c.status = Status.Expired;
        _close(c);
        bondToken.safeTransfer(c.reporter, bondAmount);
        bondToken.safeTransfer(c.disputer, bondAmount);
        emit ClaimExpired(claimId);
    }

    // ═══════════════════════════ Vistas ═══════════════════════════

    function getClaim(uint256 claimId) external view returns (Claim memory) {
        return _claims[claimId];
    }

    /// @notice Cuanto se puede recortar todavia en un pool congelado.
    function slashableAmount(address pool) public view returns (uint256) {
        ICoveragePool p = ICoveragePool(pool);
        uint256 cap = Math.mulDiv(p.frozenAssetsSnapshot(), p.maxSlashBps(), BPS);
        return cap - p.slashedDuringFreeze();
    }

    // ═══════════════════════════ Internas ═══════════════════════════

    /// @dev Si se pide mas de lo que permite el cap del pool, se recorta lo maximo
    ///      en lugar de revertir: un claim valido no debe quedarse bloqueado.
    function _approve(uint256 claimId, Claim storage c, uint256 amount) internal {
        uint256 toSlash = Math.min(amount, slashableAmount(c.pool));
        c.status = Status.Approved;
        c.slashedAmount = toSlash;
        if (toSlash > 0) ICoveragePool(c.pool).slash(toSlash, c.recipient);
        _close(c);
        emit ClaimApproved(claimId, toSlash);
    }

    function _close(Claim storage c) internal {
        activeClaimOf[c.pool] = 0;
        ICoveragePool(c.pool).unfreeze();
    }
}
