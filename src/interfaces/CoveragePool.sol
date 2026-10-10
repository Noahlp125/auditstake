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

    // ───────────────────────── Configuración ─────────────────────────
    uint256 internal constant BPS = 10_000;

    IERC20 public immutable rewardToken;
    address public immutable registry;
    address public immutable claimManager;
    uint256 public immutable cooldownPeriod;
    uint256 public immutable unstakeWindow;
    uint16 public immutable maxSlashBps;

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

    /// @dev Mitiga el inflation attack del primer depositante: las shares
    ///      tienen 6 decimales extra, asi que donar para manipular el precio
    ///      cuesta ~1e6 veces mas de lo que el atacante podria robar.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /// @dev Shares no transferibles: solo mint (from = 0) y burn (to = 0).
    ///      Si se pudieran transferir, el cooldown se esquivaria moviendo
    ///      las shares a otra cuenta que ya lo tuviera cumplido.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert NonTransferable();
        super._update(from, to, value);
    }
}