'use client'

import { useSyncExternalStore } from 'react'
import { useConnect, useConnection, useConnectors, useDisconnect } from 'wagmi'
import { shortAddress } from '@/lib/format'

/**
 * Dos formas de conectarse:
 *  - "Cuenta de prueba": la cuenta (0) de Anvil, sin wallet ni firmas. Solo en local.
 *  - "MetaMask": la wallet del navegador. La que se usara en Sepolia.
 */
const noop = () => () => {}

export function ConnectButton() {
  // El servidor no sabe si estas conectada: hasta que la pagina carga en el
  // navegador se pinta un hueco, para que el HTML del servidor y el del
  // navegador coincidan (si no, React da un error de "hydration").
  const mounted = useSyncExternalStore(noop, () => true, () => false)
  const { address, isConnected, connector } = useConnection()
  const connectors = useConnectors()
  const { mutate: connect, isPending } = useConnect()
  const { mutate: disconnect } = useDisconnect()

  if (!mounted) return <span className="btn-wallet" aria-hidden="true" style={{ visibility: 'hidden' }}>0x0000…0000</span>

  if (isConnected) {
    return (
      <button
        type="button"
        className="btn-wallet"
        onClick={() => disconnect({})}
        title={`Conectado con ${connector?.name}. Pulsa para desconectar.`}
      >
        {shortAddress(address)}
      </button>
    )
  }

  const anvil = connectors.find((c) => c.type === 'mock')
  const browser = connectors.find((c) => c.type === 'injected')

  return (
    <div className="header-right">
      {anvil && (
        <button type="button" className="btn-wallet" disabled={isPending} onClick={() => connect({ connector: anvil })}>
          Cuenta de prueba
        </button>
      )}
      {browser && (
        <button type="button" className="btn-wallet" disabled={isPending} onClick={() => connect({ connector: browser })}>
          MetaMask
        </button>
      )}
    </div>
  )
}
