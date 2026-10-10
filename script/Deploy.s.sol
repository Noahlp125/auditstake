// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CoveragePool} from "../src/CoveragePool.sol";
import {ClaimManager} from "../src/ClaimManager.sol";
import {CoverageRegistry} from "../src/CoverageRegistry.sol";
import {PoolFactory} from "../src/PoolFactory.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/// @notice Despliega AuditStake completo y deja un estado de demo listo para el frontend.
///         Funciona igual en Anvil (local) y en Sepolia: solo cambia la red.
/// @dev Los tokens son MockERC20 con mint() publico: validos para local/testnet,
///      NUNCA para mainnet.
contract Deploy is Script {
    // Parametros del ClaimManager
    uint256 constant BOND = 10 ether;
    uint64 constant DISPUTE_WINDOW = 3 days;
    uint64 constant ARBITRATION_TIMEOUT = 14 days;

    // Parametros de los pools
    uint256 constant COOLDOWN = 7 days;
    uint256 constant WINDOW = 2 days;

    // Se guardan en storage para no superar el limite de variables locales
    // de la pila de la EVM ("stack too deep").
    address deployer;
    MockERC20 stakeToken;
    MockERC20 premiumToken;
    MockERC20 bondToken;
    PoolFactory factory;
    CoverageRegistry registry;
    ClaimManager cm;
    address poolLumen;
    address poolOrbit;

    function run() external {
        vm.startBroadcast();
        // La cuenta que firma (la de --private-key o --account). No uses msg.sender:
        // dentro de run() no siempre coincide con quien firma.
        (, deployer,) = vm.readCallers();

        _deployCore();
        _createPools();
        _seedDemo();

        vm.stopBroadcast();
        _save();
    }

    /// @dev Tokens de prueba + nucleo, en el orden que rompe la dependencia circular.
    function _deployCore() internal {
        stakeToken = new MockERC20("AuditStake Stake", "STK");
        premiumToken = new MockERC20("AuditStake Premium", "PRM");
        bondToken = new MockERC20("AuditStake Bond", "BND");

        factory = new PoolFactory();
        registry = new CoverageRegistry(deployer, factory);
        cm = new ClaimManager(bondToken, BOND, DISPUTE_WINDOW, ARBITRATION_TIMEOUT, address(registry), deployer);
        registry.setClaimManager(cm);
    }

    /// @dev Dos protocolos de ejemplo. El deployer hace de sponsor y de arbitro.
    function _createPools() internal {
        poolLumen = registry.createPool(
            _fakeProtocol("Lumen Lending"),
            deployer,
            stakeToken,
            premiumToken,
            COOLDOWN,
            WINDOW,
            5_000,
            "AuditStake Lumen Lending",
            "asLUMEN"
        );
        poolOrbit = registry.createPool(
            _fakeProtocol("Orbit Bridge"),
            deployer,
            stakeToken,
            premiumToken,
            COOLDOWN,
            WINDOW,
            5_000,
            "AuditStake Orbit Bridge",
            "asORBIT"
        );
    }

    /// @dev Estado de demo: el deployer respalda los dos pools y paga primas.
    function _seedDemo() internal {
        stakeToken.mint(deployer, 10_000 ether);
        premiumToken.mint(deployer, 100_000 ether);
        bondToken.mint(deployer, 1_000 ether);

        stakeToken.approve(poolLumen, type(uint256).max);
        stakeToken.approve(poolOrbit, type(uint256).max);
        premiumToken.approve(address(registry), type(uint256).max);
        bondToken.approve(address(cm), type(uint256).max);

        CoveragePool(poolLumen).deposit(300 ether, deployer);
        CoveragePool(poolOrbit).deposit(250 ether, deployer);
        registry.payPremium(poolLumen, 4_000 ether, 40 days);
        registry.payPremium(poolOrbit, 2_000 ether, 30 days);
    }

    /// @dev Direccion ficticia para un protocolo de ejemplo, derivada de su nombre.
    function _fakeProtocol(string memory name) internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes(name)))));
    }

    /// @dev Guarda las direcciones en deployments/<chainId>.json para el frontend.
    function _save() internal {
        string memory k = "deployment";
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeAddress(k, "deployer", deployer);
        vm.serializeAddress(k, "stakeToken", address(stakeToken));
        vm.serializeAddress(k, "premiumToken", address(premiumToken));
        vm.serializeAddress(k, "bondToken", address(bondToken));
        vm.serializeAddress(k, "poolFactory", address(factory));
        vm.serializeAddress(k, "registry", address(registry));
        vm.serializeAddress(k, "claimManager", address(cm));
        vm.serializeAddress(k, "poolLumen", poolLumen);
        string memory json = vm.serializeAddress(k, "poolOrbit", poolOrbit);

        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);

        console.log("Registry     ", address(registry));
        console.log("ClaimManager ", address(cm));
        console.log("Pool Lumen   ", poolLumen);
        console.log("Pool Orbit   ", poolOrbit);
        console.log("Guardado en  ", path);
    }
}
