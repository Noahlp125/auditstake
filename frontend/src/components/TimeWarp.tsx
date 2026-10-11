'use client'

import { useState } from 'react'
import { createTestClient, http } from 'viem'
import { foundry } from 'wagmi/chains'
import { useChainId } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'

// Cliente de pruebas de viem: habla con los metodos especiales de Anvil.
const testClient = createTestClient({ mode: 'anvil', chain: foundry, transport: http('http://127.0.0.1:8545') })

const JUMPS = [
  { label: '+1h', seconds: 3600 },
  { label: '+1d', seconds: 86400 },
  { label: '+7d', seconds: 7 * 86400 },
]

/** Adelanta el reloj de Anvil sin salir de la app. Solo aparece en la red local. */
export function TimeWarp() {
  const chainId = useChainId()
  const queryClient = useQueryClient()
  const [busy, setBusy] = useState(false)

  if (chainId !== foundry.id) return null

  async function jump(seconds: number) {
    setBusy(true)
    try {
      await testClient.increaseTime({ seconds })
      await testClient.mine({ blocks: 1 })
      await queryClient.invalidateQueries()
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="timewarp" role="group" aria-label="Adelantar el reloj de Anvil">
      <span>Tiempo</span>
      {JUMPS.map((j) => (
        <button key={j.label} type="button" disabled={busy} onClick={() => jump(j.seconds)}>
          {j.label}
        </button>
      ))}
    </div>
  )
}
