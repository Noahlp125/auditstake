// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Lo que el ClaimManager necesita ver de cada pool.
interface ICoveragePool {
    function freeze() external;
    function unfreeze() external;
    function slash(uint256 assets, address recipient) external;

    function frozen() external view returns (bool);
    function frozenAssetsSnapshot() external view returns (uint256);
    function slashedDuringFreeze() external view returns (uint256);
    function maxSlashBps() external view returns (uint16);
}
