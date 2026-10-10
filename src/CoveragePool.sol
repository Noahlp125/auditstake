// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CoveragePool
/// @notice Pool de staking que respalda la seguridad de UN protocolo cubierto.
contract CoveragePool is ERC4626, ReentrancyGuard {
    // ─────────────────────────── Errores ───────────────────────────
    error NonTransferable();
    error ZeroAddress();
    error SameToken();
    error InvalidBps();
    error InvalidDuration();
    error ZeroAmount();
    error ReceiverMustBeCaller();

    // ─────────────────────────── Eventos ───────────────────────────
    event CooldownStarted(address indexed staker, uint256 unlocksAt);
    event CooldownReset(address indexed staker);

    // ───────────────────────── Configuración ─────────────────────────
    uint256 internal constant BPS = 10_000;

    IERC20 public immutable rewardToken;
    address public immutable registry;
    address public immutable claimManager;
    uint256 public immutable cooldownPeriod;
    uint256 public immutable unstakeWindow;
    uint16 public immutable maxSlashBps;

    // ─────────────────────────── Cooldown ───────────────────────────
    /// @notice Momento en que cada staker inicio su cooldown (0 = sin cooldown activo).
    mapping(address => uint256) public cooldownStart;

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
        uint256 start = cooldownStart[owner];
        if (start == 0) return false;
        uint256 unlock = start + cooldownPeriod;
        return block.timestamp >= unlock && block.timestamp <= unlock + unstakeWindow;
    }

    // ═══════════════════════ ERC-4626 overrides ═══════════════════════

    /// @dev Mitiga el inflation attack del primer depositante: las shares
    ///      tienen 6 decimales extra, asi que donar para manipular el precio
    ///      cuesta ~1e6 veces mas de lo que el atacante podria robar.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
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
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (caller != receiver) revert ReceiverMustBeCaller();
        super._deposit(caller, receiver, assets, shares);
        if (cooldownStart[receiver] != 0) {
            cooldownStart[receiver] = 0;
            emit CooldownReset(receiver);
        }
    }

    /// @dev Si el owner lo retira todo, limpiamos su cooldown.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        super._withdraw(caller, receiver, owner, assets, shares);
        if (balanceOf(owner) == 0) cooldownStart[owner] = 0;
    }

    /// @dev Shares no transferibles: solo mint (from = 0) y burn (to = 0).
    ///      Si se pudieran transferir, el cooldown se esquivaria moviendo
    ///      las shares a otra cuenta que ya lo tuviera cumplido.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert NonTransferable();
        super._update(from, to, value);
    }
}
