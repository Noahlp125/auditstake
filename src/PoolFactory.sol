// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CoveragePool} from "./CoveragePool.sol";

/// @title PoolFactory
/// @notice Despliega CoveragePools. Existe solo para sacar el bytecode del pool del
///         CoverageRegistry: con el `new CoveragePool` dentro, el registry pasaba del
///         limite de 24 KB por contrato (EIP-170) y no se podria desplegar.
/// @dev Cualquiera puede llamar a deploy(), pero el pool queda con registry = msg.sender.
///      Un pool creado por un tercero no vale para nada: el ClaimManager solo acepta los
///      que registra el CoverageRegistry, y solo el registry puede pagarle primas.
contract PoolFactory {
    event PoolDeployed(address indexed pool, address indexed registry);

    function deploy(
        IERC20 stakeToken,
        IERC20 premiumToken,
        address claimManager,
        uint256 cooldownPeriod,
        uint256 unstakeWindow,
        uint16 maxSlashBps,
        string calldata name,
        string calldata symbol
    ) external returns (address pool) {
        pool = address(
            new CoveragePool(
                stakeToken,
                premiumToken,
                msg.sender, // el registry que llama
                claimManager,
                cooldownPeriod,
                unstakeWindow,
                maxSlashBps,
                name,
                symbol
            )
        );
        emit PoolDeployed(pool, msg.sender);
    }
}
