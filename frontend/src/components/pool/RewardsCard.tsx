'use client'

import { formatUnits } from 'viem'
import { coveragePoolAbi } from '@/lib/contracts'
import { formatDuration, formatNumber } from '@/lib/format'
import { PRECISION } from '@/lib/rewards'
import type { PoolData } from '@/hooks/usePool'
import type { useTx } from '@/hooks/useTx'

type Props = {
  pool: `0x${string}`
  data: PoolData
  now: number | undefined
  blockTime: number | undefined
  tx: ReturnType<typeof useTx>
  connected: boolean
}

/**
 * El contador sube en directo: parte de earned() leido en el ultimo bloque y le
 * suma lo que el usuario gana por segundo desde entonces. Se resincroniza en cada
 * lectura nueva, asi que nunca se separa de lo que dice el contrato.
 */
export function RewardsCard({ pool, data, now, blockTime, tx, connected }: Props) {
  const { rewardRate, shares, totalSupply, earned, periodFinish } = data

  // Recompensa del usuario por segundo, en wei de PRM
  const perSecondWei = totalSupply > 0n ? (rewardRate * shares) / totalSupply / PRECISION : 0n
  const perSecond = Number(formatUnits(perSecondWei, 18))

  let live = Number(formatUnits(earned, 18))
  if (now !== undefined && blockTime !== undefined) {
    const until = Math.min(now, periodFinish)
    const elapsed = Math.max(0, until - blockTime)
    live += perSecond * elapsed
  }

  const running = now !== undefined && now < periodFinish
  const share = totalSupply > 0n ? Number((shares * 10000n) / totalSupply) / 100 : 0

  return (
    <section aria-label="Recompensas" className="card dark" style={{ flexDirection: 'row', flexWrap: 'wrap', alignItems: 'flex-end', justifyContent: 'space-between', gap: 24 }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--dark-muted)' }}>
          <span className={`dot ${running && shares > 0n ? '' : 'off'}`} />
          {running && shares > 0n ? 'Recompensas acumulándose ahora' : 'Recompensas acumuladas'}
        </span>
        <span className="mono" style={{ fontSize: 44, fontWeight: 500, letterSpacing: '-0.02em' }}>
          {formatNumber(live, 4)} <span style={{ fontSize: 20, color: 'var(--dark-muted)' }}>PRM</span>
        </span>
        <span style={{ fontSize: 14, color: 'var(--dark-muted)' }}>
          {shares > 0n
            ? `+${formatNumber(perSecond * 3600, 2)} PRM por hora · ${formatNumber(share, 1)}% del pool · `
            : 'Deposita stake para empezar a cobrar · '}
          {running ? `la prima termina en ${formatDuration(periodFinish - (now ?? 0))}` : 'no hay prima en curso'}
        </span>
      </div>
      <button
        type="button"
        className="btn btn-light"
        disabled={!connected || earned === 0n || tx.pending !== null}
        onClick={() => tx.run('claim', { address: pool, abi: coveragePoolAbi, functionName: 'claimRewards' })}
      >
        {tx.pending === 'claim' ? 'Cobrando…' : 'Cobrar recompensas'}
      </button>
    </section>
  )
}
