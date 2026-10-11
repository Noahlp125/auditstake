import { formatDuration, formatToken } from '@/lib/format'
import { annualPremium } from '@/lib/rewards'
import type { PoolData } from '@/hooks/usePool'

export function PoolStats({ data, now }: { data: PoolData; now: number | undefined }) {
  const rows = [
    ['Stake total', `${formatToken(data.totalAssets)} STK`],
    ['Prima anualizada', `${formatToken(annualPremium(data.rewardRate, BigInt(data.periodFinish), now), 0)} PRM`],
    ['Slash máximo por claim', `${data.maxSlashBps / 100}%`],
    ['Cooldown · ventana', `${formatDuration(data.cooldownPeriod)} · ${formatDuration(data.unstakeWindow)}`],
  ]
  return (
    <section aria-label="Datos del pool" className="card compact" style={{ gap: 4 }}>
      <h2 style={{ marginBottom: 8 }}>El pool</h2>
      {rows.map(([label, value]) => (
        <div key={label} className="row">
          <span className="muted">{label}</span>
          <span className="mono">{value}</span>
        </div>
      ))}
    </section>
  )
}
