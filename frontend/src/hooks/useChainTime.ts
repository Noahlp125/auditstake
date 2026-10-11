'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useBlock } from 'wagmi'

/**
 * Hora de la blockchain, no la del ordenador. Importa porque en Anvil podemos
 * adelantar el reloj (evm_increaseTime) y los contratos usan block.timestamp.
 *
 * Devuelve el timestamp del ultimo bloque mas los segundos que han pasado desde
 * que lo vimos, recalculado cada `tickMs`. Asi los contadores avanzan suaves
 * entre bloque y bloque y se resincronizan con cada bloque nuevo.
 */
export function useChainTime(tickMs = 1000) {
  const { data: block } = useBlock({ watch: true })
  const lastBlock = useRef<{ timestamp: number; seenAt: number } | null>(null)
  const [now, setNow] = useState<number | undefined>(undefined)

  // Hora del ultimo bloque + tiempo transcurrido desde que lo vimos
  const update = useCallback(() => {
    const b = lastBlock.current
    setNow(b ? b.timestamp + (Date.now() - b.seenAt) / 1000 : undefined)
  }, [])

  // Cada bloque nuevo: apuntamos su hora y cuando lo vimos, y recalculamos ya
  useEffect(() => {
    if (!block) return
    lastBlock.current = { timestamp: Number(block.timestamp), seenAt: Date.now() }
    const t = setTimeout(update, 0)
    return () => clearTimeout(t)
  }, [block, update])

  // Y ademas cada `tickMs`, para que los contadores avancen entre bloques
  useEffect(() => {
    const id = setInterval(update, tickMs)
    return () => clearInterval(id)
  }, [tickMs, update])

  return { now, blockTime: block ? Number(block.timestamp) : undefined }
}
