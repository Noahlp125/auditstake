import { createConfig, http, injected, mock } from 'wagmi'
import { IS_LOCAL, RPC_URL, TARGET_CHAIN } from './network'

// Cuenta (0) de Anvil: es publica y esta desbloqueada en el nodo local, asi que
// Anvil firma por nosotros. SOLO sirve en local; en Sepolia se usa MetaMask.
export const ANVIL_ACCOUNT_0 = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' as const

export const config = createConfig({
  chains: [TARGET_CHAIN],
  connectors: IS_LOCAL
    ? [
        injected(), // MetaMask u otra wallet del navegador
        // defaultConnected + reconnect: tras conectar una vez, sigue conectada al recargar
        mock({ accounts: [ANVIL_ACCOUNT_0], features: { defaultConnected: true, reconnect: true } }),
      ]
    : [injected()], // en una red publica, solo wallets reales
  transports: {
    [TARGET_CHAIN.id]: http(RPC_URL),
  },
  ssr: true,
})

declare module 'wagmi' {
  interface Register {
    config: typeof config
  }
}
