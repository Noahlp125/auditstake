'use client'

import Link from 'next/link'
import { usePools } from '@/hooks/usePools'
import { FaucetCard } from '@/components/FaucetCard'
import { useChainTime } from '@/hooks/useChainTime'
import { annualPremium } from '@/lib/rewards'
import { errorMessage, formatDuration, formatToken, shortAddress } from '@/lib/format'

function LockIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <rect x="5" y="11" width="14" height="10" rx="2" />
      <path d="M8 11V7a4 4 0 0 1 8 0v4" />
    </svg>
  )
}

export function StatusChip({ frozen }: { frozen: boolean }) {
  return frozen ? (
    <span className="chip chip-frozen"><LockIcon />Congelado</span>
  ) : (
    <span className="chip chip-active"><span className="dot" />Activo</span>
  )
}

export function ExploreView() {
  const { pools, isLoading, error } = usePools()
  const { now } = useChainTime(5000)

  const totalStake = pools?.reduce((acc, p) => acc + p.totalAssets, 0n) ?? 0n
  const totalPremium = pools?.reduce((acc, p) => acc + annualPremium(p.rewardRate, p.periodFinish, now), 0n) ?? 0n
  const frozenCount = pools?.filter((p) => p.frozen).length ?? 0

  return (
    <main className="container" style={{ gap: 48, paddingTop: 56 }}>
      <section style={{ display: 'flex', flexDirection: 'column', gap: 16, maxWidth: 760 }}>
        <p className="mono" style={{ fontSize: 13, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--accent)' }}>
          Seguro descentralizado de smart contracts
        </p>
        <h1 style={{ fontSize: 48, lineHeight: 1.05, letterSpacing: '-0.02em' }}>Auditores que se juegan su stake.</h1>
        <p style={{ fontSize: 18, lineHeight: 1.55, color: 'var(--ink-2)' }}>
          Cada pool respalda la seguridad de un protocolo. Mientras no haya exploits, los auditores cobran la
          prima del protocolo. Si lo hay, su stake compensa a los afectados.
        </p>
      </section>

      <section aria-label="Resumen" className="card" style={{ padding: 0, gap: 0, overflow: 'hidden' }}>
        <div className="stats" style={{ gap: 1, background: 'var(--line)', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))' }}>
          {[
            { label: 'Stake total respaldando', value: `${formatToken(totalStake, 0)} STK` },
            { label: 'Prima anualizada en curso', value: `${formatToken(totalPremium, 0)} PRM` },
            { label: 'Protocolos cubiertos', value: String(pools?.length ?? '—') },
            { label: 'Claims abiertos', value: String(frozenCount), alert: frozenCount > 0 },
          ].map((s) => (
            <div key={s.label} className="stat" style={{ background: 'var(--surface)', padding: '20px 24px', gap: 6 }}>
              <span className="stat-label">{s.label}</span>
              <span className="stat-value" style={{ fontSize: 28, color: s.alert ? 'var(--alert)' : undefined }}>{s.value}</span>
            </div>
          ))}
        </div>
      </section>

      <FaucetCard />

      <section style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <h2 style={{ fontSize: 24, fontWeight: 600 }}>Pools de cobertura</h2>

        {error && <p className="error">No se pudo leer el registry: {errorMessage(error)}</p>}
        {isLoading && <p className="muted">Cargando pools…</p>}

        {pools && (
          <div className="table-box">
            <table className="table">
              <thead>
                <tr>
                  <th scope="col">Protocolo</th>
                  <th scope="col" style={{ textAlign: 'right' }}>Stake</th>
                  <th scope="col" style={{ textAlign: 'right' }}>Prima / año</th>
                  <th scope="col" style={{ textAlign: 'right' }}>Slash máx.</th>
                  <th scope="col" style={{ textAlign: 'right' }}>Cooldown</th>
                  <th scope="col">Estado</th>
                </tr>
              </thead>
              <tbody>
                {pools.map((p) => (
                  <tr key={p.address} className={p.frozen ? 'is-frozen' : undefined}>
                    <td>
                      <Link href={`/pool/${p.address}`} className="pool-link">
                        <span>{p.name}</span>
                        <span className="mono muted" style={{ fontSize: 12 }}>{shortAddress(p.protocol)}</span>
                      </Link>
                    </td>
                    <td className="num">{formatToken(p.totalAssets, 0)} STK</td>
                    <td className="num">{formatToken(annualPremium(p.rewardRate, p.periodFinish, now), 0)} PRM</td>
                    <td className="num">{p.maxSlashBps / 100}%</td>
                    <td className="num">{formatDuration(Number(p.cooldownPeriod))} + {formatDuration(Number(p.unstakeWindow))}</td>
                    <td><StatusChip frozen={p.frozen} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </main>
  )
}
