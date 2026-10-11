'use client'

import { useState } from 'react'
import { useConfig, useWriteContract } from 'wagmi'
import { waitForTransactionReceipt } from 'wagmi/actions'
import { useQueryClient } from '@tanstack/react-query'
import { errorMessage } from '@/lib/format'

/**
 * Envia una transaccion, espera a que se mine y refresca todas las lecturas.
 * `pending` dice que accion esta en curso, para deshabilitar botones.
 */
export function useTx() {
  const config = useConfig()
  const queryClient = useQueryClient()
  const { mutateAsync: writeContractAsync } = useWriteContract()
  const [pending, setPending] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function run(label: string, ...calls: Parameters<typeof writeContractAsync>[0][]) {
    setPending(label)
    setError(null)
    try {
      // Varias llamadas en orden: p. ej. approve y luego deposit
      for (const call of calls) {
        const hash = await writeContractAsync(call)
        const receipt = await waitForTransactionReceipt(config, { hash })
        if (receipt.status !== 'success') throw new Error('La transacción ha revertido')
      }
      await queryClient.invalidateQueries()
      return true
    } catch (e) {
      setError(errorMessage(e))
      return false
    } finally {
      setPending(null)
    }
  }

  return { run, pending, error }
}
