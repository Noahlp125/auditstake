'use client'

import { coveragePoolAbi } from '@/lib/contracts'
import { formatDate, formatDuration, formatNumber, formatToken } from '@/lib/format'
import type { PoolData } from '@/hooks/usePool'
import type { useTx } from '@/hooks/useTx'

type Props = {
  pool: `0x${string}`
  user: `0x${string}` | undefined
  data: PoolData
  now: number | undefined
  tx: ReturnType<typeof useTx>
}

type Phase = 'none' | 'cooldown' | 'window' | 'expired'

/** En que punto del cooldown esta el usuario (misma logica que canWithdraw). */
function phaseOf(start: number, cooldown: number, window: number, now: number): Phase {
  if (start === 0) return 'none'
  const unlock = start + cooldown
  if (now < unlock) return 'cooldown'
  if (now <= unlock + window) return 'window'
  return 'expired'
}

export function PositionCard({ pool, user, data, now, tx }: Props) {
  const { shares, userAssets, maxSlashBps, cooldownStart, cooldownPeriod, unstakeWindow, frozen, maxRedeem } = data
  const maxLoss = (userAssets * BigInt(maxSlashBps)) / 10000n
  const sharePct = data.totalSupply > 0n ? Number((shares * 10000n) / data.totalSupply) / 100 : 0
  const phase = now !== undefined ? phaseOf(cooldownStart, cooldownPeriod, unstakeWindow, now) : 'none'

  const unlock = cooldownStart + cooldownPeriod
  const close = unlock + unstakeWindow
  const total = cooldownPeriod + unstakeWindow
  const progress = now !== undefined && cooldownStart > 0 ? Math.min(1, Math.max(0, (now - cooldownStart) / total)) : 0
  const cooldownShare = total > 0 ? cooldownPeriod / total : 0.78

  const startCooldown = () =>
    tx.run('cooldown', { address: pool, abi: coveragePoolAbi, functionName: 'startCooldown' })
  const withdraw = () =>
    user &&
    tx.run('withdraw', { address: pool, abi: coveragePoolAbi, functionName: 'redeem', args: [maxRedeem, user, user] })

  return (
    <section aria-label="Tu posición" className="card" style={{ gap: 24 }}>
      <h2>Tu posición</h2>
      <div className="stats">
        <div className="stat"><span className="stat-label">Tu parte del pool</span><span className="stat-value">{formatNumber(sharePct, 1)}%</span></div>
        <div className="stat"><span className="stat-label">Valor actual</span><span className="stat-value">{formatToken(userAssets)} STK</span></div>
        <div className="stat"><span className="stat-label">Pérdida máxima por claim</span><span className="stat-value" style={{ color: 'var(--alert)' }}>{formatToken(maxLoss)} STK</span></div>
      </div>

      {shares > 0n && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, paddingTop: 20, borderTop: '1px solid var(--line-soft)' }}>
          <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: 8, alignItems: 'baseline' }}>
            <h3 style={{ fontSize: 16, fontWeight: 600 }}>
              {phase === 'none' && 'Sin cooldown'}
              {phase === 'cooldown' && 'Cooldown en curso'}
              {phase === 'window' && 'Ventana de retirada abierta'}
              {phase === 'expired' && 'La ventana de retirada caducó'}
            </h3>
            {now !== undefined && phase === 'cooldown' && (
              <span>Podrás retirar en <strong className="mono" style={{ fontWeight: 500 }}>{formatDuration(unlock - now)}</strong></span>
            )}
            {now !== undefined && phase === 'window' && (
              <span>Se cierra en <strong className="mono" style={{ fontWeight: 500 }}>{formatDuration(close - now)}</strong></span>
            )}
          </div>

          {phase !== 'none' && (
            <>
              <div className="timeline" role="img" aria-label={`Cooldown completado al ${Math.round(progress * 100)}%`}>
                <div className="timeline-label" style={{ left: `${progress * 100}%`, transform: `translateX(-${progress * 100}%)` }}>ahora</div>
                <div className="timeline-marker" style={{ left: `${progress * 100}%` }} />
                <div className="timeline-bar">
                  <div className="timeline-cooldown" style={{ flex: `${cooldownShare} 1 0` }}>
                    <div className="timeline-fill" style={{ width: `${Math.min(1, progress / cooldownShare) * 100}%` }} />
                  </div>
                  <div className="timeline-window" style={{ flex: `${1 - cooldownShare} 1 0` }} />
                </div>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, fontSize: 13, color: 'var(--muted)', flexWrap: 'wrap' }}>
                <span>Inicio · {formatDate(cooldownStart)}</span>
                <span>Ventana · {formatDate(unlock)}</span>
                <span>Cierra · {formatDate(close)}</span>
              </div>
            </>
          )}

          <p style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--ink-2)' }}>
            {phase === 'none' &&
              `Para retirar, inicia el cooldown: tras ${formatDuration(cooldownPeriod)} tendrás ${formatDuration(unstakeWindow)} para sacar tu stake. Mientras tanto sigue cubriendo el protocolo y cobrando prima.`}
            {phase === 'cooldown' && 'Tu stake sigue cubriendo el protocolo y cobrando prima mientras esperas.'}
            {phase === 'window' && 'Puedes retirar todo tu stake ahora. Si dejas pasar la ventana, tendrás que empezar otra vez.'}
            {phase === 'expired' && 'Inicia otro cooldown si quieres retirar.'}
          </p>

          <div className="btn-row">
            <button
              type="button"
              className="btn btn-primary"
              disabled={phase !== 'window' || frozen || maxRedeem === 0n || tx.pending !== null}
              onClick={withdraw}
            >
              {tx.pending === 'withdraw' ? 'Retirando…' : frozen ? 'Retirar · bloqueado por un claim' : 'Retirar todo'}
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={tx.pending !== null || phase === 'window'}
              onClick={startCooldown}
            >
              {tx.pending === 'cooldown' ? 'Enviando…' : phase === 'none' ? 'Iniciar cooldown' : 'Reiniciar cooldown'}
            </button>
          </div>
        </div>
      )}
    </section>
  )
}
