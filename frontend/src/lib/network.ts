import type { Chain } from 'viem'
import { foundry, sepolia } from 'wagmi/chains'

/**
 * Red a la que apunta la app. Se elige con la variable NEXT_PUBLIC_NETWORK
 * (en .env.local): "local" = Anvil, "sepolia" = testnet publica.
 */
export const NETWORK = process.env.NEXT_PUBLIC_NETWORK === 'sepolia' ? 'sepolia' : 'local'

export const TARGET_CHAIN: Chain = NETWORK === 'sepolia' ? sepolia : foundry
export const IS_LOCAL = NETWORK === 'local'

export const NETWORK_LABEL = IS_LOCAL ? 'Anvil' : 'Sepolia'

/** RPC: Anvil en local; en Sepolia el que pongas en .env.local (o uno publico por defecto). */
export const RPC_URL = IS_LOCAL
  ? 'http://127.0.0.1:8545'
  : (process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL ?? 'https://ethereum-sepolia-rpc.publicnode.com')

/** Enlace al explorador de bloques (solo en Sepolia; Anvil no tiene). */
export function explorerUrl(address: string): string | undefined {
  return IS_LOCAL ? undefined : `https://sepolia.etherscan.io/address/${address}`
}
