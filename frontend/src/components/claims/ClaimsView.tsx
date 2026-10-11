'use client'

import Link from 'next/link'
import { useConnection } from 'wagmi'
import { useClaims, type Claim } from '@/hooks/useClaims'
import { usePools } from '@/hooks/usePools'
import { useChainTime } from '@/hooks/useChainTime'
import { useTx } from '@/hooks/useTx'
import { formatDuration, formatToken, shortAddress } from '@/lib/format'
import { ClaimStatusChip } from './ClaimStatusChip'
import { SubmitClaimForm } from './SubmitClaimForm'

export function ClaimsView() {
  const { address: user } = useConnection()
  const { claims } = useClaims()
  const { pools } = usePools()
  const { now } = useChainTime(1000)
  const tx = useTx()

  const nameOf = (pool: string) => pools?.find((p) => p.address === pool)?.name ?? shortAddress(pool)
  const nextId = BigInt((claims?.length ?? 0) + 1)

  function phase(c: Claim) {
    if (now === undefined) return ''
    if (c.status === 'Pending') return now <= c.disputeDeadline ? `cierra en ${formatDuration(c.disputeDeadline - now)}` : 'listo para finalizar'
    if (c.status === 'Disputed') return now <= c.arbitrationDeadline ? `árbitro: ${formatDuration(c.arbitrationDeadline - now)}` : 'puede expirar'
    if (c.status === 'Approved') return `recortados ${formatToken(c.slashedAmount)} STK`
    return ''
  }

  return (
    <main className="container">
      <section style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <h1 style={{ fontSize: 40, lineHeight: 1.1, letterSpacing: '-0.02em' }}>Claims</h1>
        <p style={{ fontSize: 16, color: 'var(--ink-2)', maxWidth: 720 }}>
          Reportes de exploit sobre los protocolos cubiertos. Un claim abierto congela su pool hasta que se resuelve.
        </p>
      </section>

      {tx.error && <p className="error" role="alert">{tx.error}</p>}

      <div className="two-col">
        <div className="col-main">
          {claims === undefined && <p className="muted">Cargando claims…</p>}
          {claims?.length === 0 && (
            <div className="card"><p className="muted">Todavía no se ha reportado ningún exploit. Puedes probar con el formulario.</p></div>
          )}
          {claims && claims.length > 0 && (
            <div className="table-box">
              <table className="table" style={{ minWidth: 640 }}>
                <thead>
                  <tr>
                    <th scope="col">Claim</th>
                    <th scope="col">Pool</th>
                    <th scope="col" style={{ textAlign: 'right' }}>Pedido</th>
                    <th scope="col">Estado</th>
                  </tr>
                </thead>
                <tbody>
                  {claims.map((c) => (
                    <tr key={c.id.toString()}>
                      <td><Link href={`/claims/${c.id}`} className="pool-link"><span>#{c.id.toString()}</span><span className="mono muted" style={{ fontSize: 12 }}>por {shortAddress(c.reporter)}</span></Link></td>
                      <td><Link href={`/pool/${c.pool}`} style={{ color: 'var(--ink)' }}>{nameOf(c.pool)}</Link></td>
                      <td className="num">{formatToken(c.requestedAmount)} STK</td>
                      <td>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-start' }}>
                          <ClaimStatusChip status={c.status} />
                          <span style={{ fontSize: 12, color: 'var(--muted)' }}>{phase(c)}</span>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
        <aside className="col-side">
          {pools && <SubmitClaimForm pools={pools} user={user} tx={tx} nextId={nextId} />}
        </aside>
      </div>
    </main>
  )
}
