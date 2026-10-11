import { createConfig, http, injected, mock } from 'wagmi'
import { foundry } from 'wagmi/chains'

// Cuenta (0) de Anvil: es publica y esta desbloqueada en el nodo local, asi que
// Anvil firma por nosotros. SOLO sirve en local; en Sepolia se usa MetaMask.
export const ANVIL_ACCOUNT_0 = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' as const

export const config = createConfig({
  chains: [foundry],
  connectors: [
    injected(), // MetaMask u otra wallet del navegador
    // defaultConnected + reconnect: tras conectar una vez, sigue conectada al recargar
    mock({ accounts: [ANVIL_ACCOUNT_0], features: { defaultConnected: true, reconnect: true } }),
  ],
  transports: {
    [foundry.id]: http('http://127.0.0.1:8545'),
  },
  ssr: true,
})

declare module 'wagmi' {
  interface Register {
    config: typeof config
  }
}
