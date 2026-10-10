// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CoveragePool
/// @notice Pool de staking que respalda la seguridad de UN protocolo cubierto.
contract CoveragePool is ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────── Errores ───────────────────────────
    error NonTransferable();
    error ZeroAddress();
    error SameToken();
    error InvalidBps();
    error InvalidDuration();
    error ZeroAmount();
    error ReceiverMustBeCaller();
    error NotRegistry();
    error NotClaimManager();
    error PoolFrozen();
    error PoolNotFrozen();
    error SlashExceedsCap(uint256 requested, uint256 available);

    // ─────────────────────────── Eventos ───────────────────────────
    event CooldownStarted(address indexed staker, uint256 unlocksAt);
    event CooldownReset(address indexed staker);
    event RewardNotified(uint256 amount, uint256 duration, uint256 periodFinish);
    event RewardPaid(address indexed staker, uint256 amount);
    event Frozen(uint256 assetsSnapshot);
    event Unfrozen(uint256 totalSlashed);
    event Slashed(address indexed recipient, uint256 assets);

    // ───────────────────────── Configuración ─────────────────────────
    uint256 internal constant BPS = 10_000;
    uint256 internal constant PRECISION = 1e36; // ver nota en rewardPerShare()

    IERC20 public immutable rewardToken;
    address public immutable registry;
    address public immutable claimManager;
    uint256 public immutable cooldownPeriod;
    uint256 public immutable unstakeWindow;
    uint16 public immutable maxSlashBps;

    // ─────────────────────────── Cooldown ───────────────────────────
    /// @notice Momento en que cada staker inicio su cooldown (0 = sin cooldown activo).
    mapping(address => uint256) public cooldownStart;

    // ─────────────────── Recompensas (estilo Synthetix) ───────────────────
    uint256 public periodFinish; // cuando termina de repartirse la prima actual
    uint256 public rewardRate; // tokens por segundo, escalado por PRECISION
    uint256 public lastUpdateTime; // ultimo checkpoint global
    uint256 public rewardPerShareStored; // acumulado global, escalado por PRECISION
    mapping(address => uint256) public userRewardPerSharePaid; // "foto" del acumulado por usuario
    mapping(address => uint256) public rewards; // recompensas devengadas y no cobradas

    // ─────────────────────────── Slashing ───────────────────────────
    bool public frozen; // true mientras hay un claim abierto
    uint256 public frozenAssetsSnapshot; // totalAssets() al congelar: base del cap
    uint256 public slashedDuringFreeze; // suma de slashes durante este congelamiento

    modifier onlyRegistry() {
        if (msg.sender != registry) revert NotRegistry();
        _;
    }

    modifier onlyClaimManager() {
        if (msg.sender != claimManager) revert NotClaimManager();
        _;
    }

    constructor(
        IERC20 asset_,
        IERC20 rewardToken_,
        address registry_,
        address claimManager_,
        uint256 cooldownPeriod_,
        uint256 unstakeWindow_,
        uint16 maxSlashBps_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(asset_) {
        if (
            address(asset_) == address(0) || address(rewardToken_) == address(0) || registry_ == address(0)
                || claimManager_ == address(0)
        ) revert ZeroAddress();
        // Si la prima se pagara en el mismo token del stake, inflaria totalAssets()
        // y los stakers podrian retirar prima como si fuera principal.
        if (address(asset_) == address(rewardToken_)) revert SameToken();
        if (maxSlashBps_ == 0 || maxSlashBps_ > BPS) revert InvalidBps();
        if (unstakeWindow_ == 0) revert InvalidDuration();

        rewardToken = rewardToken_;
        registry = registry_;
        claimManager = claimManager_;
        cooldownPeriod = cooldownPeriod_;
        unstakeWindow = unstakeWindow_;
        maxSlashBps = maxSlashBps_;
    }

    // ═══════════════════════════ Cooldown ═══════════════════════════

    /// @notice Inicia el cooldown. Tras `cooldownPeriod` se abre una ventana de
    ///         `unstakeWindow` segundos para retirar. Durante el cooldown el stake
    ///         sigue en riesgo: no se puede salir corriendo al intuir un exploit.
    function startCooldown() external {
        if (balanceOf(msg.sender) == 0) revert ZeroAmount();
        cooldownStart[msg.sender] = block.timestamp;
        emit CooldownStarted(msg.sender, block.timestamp + cooldownPeriod);
    }

    /// @notice True solo si el owner esta dentro de su ventana de retirada.
    function canWithdraw(address owner) public view returns (bool) {
        if (frozen) return false;
        uint256 start = cooldownStart[owner];
        if (start == 0) return false;
        uint256 unlock = start + cooldownPeriod;
        return block.timestamp >= unlock && block.timestamp <= unlock + unstakeWindow;
    }

    // ═══════════════════════════ Recompensas ═══════════════════════════

    /// @notice El reparto se detiene al llegar a periodFinish.
    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    /// @notice Recompensa acumulada por cada share desde el inicio (escalada por PRECISION).
    /// @dev PRECISION = 1e36 en vez del clasico 1e18: con el offset de 6 decimales,
    ///      100 tokens son 1e26 shares. Con 1e18, el incremento por segundo
    ///      (rate * 1e18 / 1e26) se truncaria a 0 y las recompensas se perderian
    ///      en silencio. mulDiv evita el overflow del producto intermedio.
    function rewardPerShare() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return rewardPerShareStored;
        return rewardPerShareStored + Math.mulDiv(lastTimeRewardApplicable() - lastUpdateTime, rewardRate, supply);
    }

    /// @notice Recompensas que `account` puede cobrar ahora mismo.
    function earned(address account) public view returns (uint256) {
        return Math.mulDiv(balanceOf(account), rewardPerShare() - userRewardPerSharePaid[account], PRECISION)
            + rewards[account];
    }

    /// @dev Checkpoint: cierra el tramo de tiempo transcurrido y apunta lo que
    ///      lleva ganado `account` ANTES de que cambie su balance.
    function _updateReward(address account) internal {
        rewardPerShareStored = rewardPerShare();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerSharePaid[account] = rewardPerShareStored;
        }
    }

    /// @notice El registry deposita la prima del protocolo y la reparte en streaming
    ///         durante `duration` segundos. Si queda prima pendiente del periodo
    ///         anterior, se suma a la nueva.
    /// @dev Se mide el balance recibido en lugar de fiarse de `amount`: asi se
    ///      soportan tokens con comision por transferencia (fee-on-transfer).
    function notifyRewardAmount(uint256 amount, uint256 duration) external nonReentrant onlyRegistry {
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert InvalidDuration();
        _updateReward(address(0));

        uint256 balBefore = rewardToken.balanceOf(address(this));
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = rewardToken.balanceOf(address(this)) - balBefore;

        uint256 leftover;
        if (block.timestamp < periodFinish) {
            leftover = (periodFinish - block.timestamp) * rewardRate; // ya escalado
        }
        rewardRate = (received * PRECISION + leftover) / duration;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;

        emit RewardNotified(received, duration, periodFinish);
    }

    /// @notice Cobra las recompensas devengadas.
    /// @dev Patron checks-effects-interactions: se pone a 0 antes de transferir.
    function claimRewards() external nonReentrant returns (uint256 reward) {
        _updateReward(msg.sender);
        reward = rewards[msg.sender];
        if (reward == 0) return 0;
        rewards[msg.sender] = 0;
        rewardToken.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    // ═══════════════════════════ Slashing ═══════════════════════════

    /// @notice Se llama al abrirse un claim: nadie entra ni sale hasta resolverlo.
    ///         Se guarda una foto de los activos para calcular el cap de slashing.
    function freeze() external onlyClaimManager {
        if (frozen) revert PoolFrozen();
        frozen = true;
        frozenAssetsSnapshot = totalAssets();
        slashedDuringFreeze = 0;
        emit Frozen(frozenAssetsSnapshot);
    }

    /// @notice Se llama al resolver el claim (aprobado o rechazado).
    function unfreeze() external onlyClaimManager {
        if (!frozen) revert PoolNotFrozen();
        frozen = false;
        emit Unfrozen(slashedDuringFreeze);
    }

    /// @notice Recorta activos del vault y los envia a `recipient` (el contrato que
    ///         compensara a los afectados). No se queman shares: baja el valor de
    ///         cada share, asi que todos los stakers pierden en proporcion.
    /// @dev El cap es ACUMULADO sobre la foto tomada al congelar. Si fuera por
    ///      llamada, varios slashes pequenos podrian sumar mas que el maximo
    ///      (5 x 20% ya vacia el pool aunque cada uno respete un cap del 50%).
    function slash(uint256 assets, address recipient) external nonReentrant onlyClaimManager {
        if (!frozen) revert PoolNotFrozen();
        if (assets == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        uint256 cap = Math.mulDiv(frozenAssetsSnapshot, maxSlashBps, BPS);
        uint256 available = cap - slashedDuringFreeze;
        if (assets > available) revert SlashExceedsCap(assets, available);

        slashedDuringFreeze += assets;
        IERC20(asset()).safeTransfer(recipient, assets);
        emit Slashed(recipient, assets);
    }

    // ═══════════════════════ ERC-4626 overrides ═══════════════════════

    /// @dev Mitiga el inflation attack del primer depositante: las shares
    ///      tienen 6 decimales extra, asi que donar para manipular el precio
    ///      cuesta ~1e6 veces mas de lo que el atacante podria robar.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /// @dev Con el pool congelado no entra nadie (ver _deposit).
    function maxDeposit(address) public view override returns (uint256) {
        return frozen ? 0 : type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        return frozen ? 0 : type(uint256).max;
    }

    /// @dev withdraw() y redeem() de OpenZeppelin comprueban estos limites y
    ///      revierten si se pide mas. Fuera de la ventana, el limite es 0.
    function maxWithdraw(address owner) public view override returns (uint256) {
        return canWithdraw(owner) ? super.maxWithdraw(owner) : 0;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return canWithdraw(owner) ? super.maxRedeem(owner) : 0;
    }

    /// @dev Dos reglas que van juntas:
    ///      1. Solo puedes depositar para ti mismo (caller == receiver). Si se permitiera
    ///         depositar a favor de otro, un atacante podria resetear el cooldown ajeno
    ///         con 1 wei y dejar atrapada a la victima (griefing).
    ///      2. Un deposito nuevo reinicia tu cooldown. Sin esto, alguien podria iniciar
    ///         cooldown con 1 wei, esperar, y meter un stake grande justo al abrirse la
    ///         ventana para cobrar primas casi sin estar expuesto.
    ///      Ademas, con el pool congelado no se puede depositar: el que entrara ahora
    ///      cargaria con parte del slash de un exploit que nunca respaldo, y a la vez
    ///      diluiria la perdida de los stakers que si eran responsables.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (frozen) revert PoolFrozen();
        if (caller != receiver) revert ReceiverMustBeCaller();
        super._deposit(caller, receiver, assets, shares);
        if (cooldownStart[receiver] != 0) {
            cooldownStart[receiver] = 0;
            emit CooldownReset(receiver);
        }
    }

    /// @dev Si el owner lo retira todo, limpiamos su cooldown.
    ///      El chequeo de frozen ya lo hacen maxWithdraw/maxRedeem; lo repetimos
    ///      aqui por defensa en profundidad (si un override futuro se lo salta).
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (frozen) revert PoolFrozen();
        super._withdraw(caller, receiver, owner, assets, shares);
        if (balanceOf(owner) == 0) cooldownStart[owner] = 0;
    }

    /// @dev Shares no transferibles: solo mint (from = 0) y burn (to = 0).
    ///      Si se pudieran transferir, el cooldown se esquivaria moviendo
    ///      las shares a otra cuenta que ya lo tuviera cumplido.
    ///      Ademas es el punto unico por el que pasan mint y burn, asi que aqui
    ///      hacemos el checkpoint de recompensas ANTES de cambiar balances.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert NonTransferable();
        _updateReward(from);
        _updateReward(to);
        super._update(from, to, value);
    }
}
