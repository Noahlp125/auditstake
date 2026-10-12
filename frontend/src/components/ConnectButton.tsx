'use client'

import { useSyncExternalStore } from 'react'
import { useConnect, useConnection, useConnectors, useDisconnect, useSwitchChain } from 'wagmi'
import { TARGET_CHAIN } from '@/lib/network'
import { shortAddress } from '@/lib/format'

/**
 * Dos formas de conectarse:
 *  - "Cuenta de prueba": la cuenta (0) de Anvil, sin wallet ni firmas. Solo en local.
 *  - "MetaMask": la wallet del navegador. La que se usa en Sepolia.
 */
const noop = () => () => {}

export function ConnectButton() {
  // Hasta que la pagina carga en el navegador se pinta un hueco, para que el HTML
  // del servidor y el del navegador coincidan (si no, error de "hydration").
  const mounted = useSyncExternalStore(noop, () => true, () => false)
  const { address, isConnected, connector, chainId } = useConnection()
  const { mutate: switchChain, isPending: switching } = useSwitchChain()
  const connectors = useConnectors()
  const { mutate: connect, isPending } = useConnect()
  const { mutate: disconnect } = useDisconnect()

  if (!mounted) return <span className="btn-wallet" aria-hidden="true" style={{ visibility: 'hidden' }}>0x0000…0000</span>

  // MetaMask conectado a otra red (p. ej. Ethereum mainnet): ofrecemos cambiar
  if (isConnected && chainId !== TARGET_CHAIN.id) {
    return (
      <button type="button" className="btn-wallet" style={{ background: 'var(--alert-soft)', color: 'var(--alert-ink)' }}
        disabled={switching} onClick={() => switchChain({ chainId: TARGET_CHAIN.id })}>
        {switching ? 'Cambiando…' : `Cambiar a ${TARGET_CHAIN.name}`}
      </button>
    )
  }

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
        <button type="button" className="btn-wallet" disabled={isPending}
          onClick={() => connect({ connector: browser, chainId: TARGET_CHAIN.id })}>
          MetaMask
        </button>
      )}
    </div>
  )
}
