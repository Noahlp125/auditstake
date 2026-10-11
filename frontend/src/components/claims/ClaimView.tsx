'use client'

import Link from 'next/link'
import { useState } from 'react'
import { useConnection, useReadContract } from 'wagmi'
import { parseUnits } from 'viem'
import { useClaim, type Claim } from '@/hooks/useClaims'
import { usePools } from '@/hooks/usePools'
import { useChainTime } from '@/hooks/useChainTime'
import { useTx } from '@/hooks/useTx'
import { claimManagerAbi, getDeployment, mockERC20Abi } from '@/lib/contracts'
import { formatDate, formatDuration, formatToken, shortAddress } from '@/lib/format'
import { ClaimStatusChip } from './ClaimStatusChip'

const ZERO = '0x0000000000000000000000000000000000000000'

function Check() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M5 12l5 5 9-10" /></svg>
  )
}

/** Las 4 fases del claim, marcando la actual. */
function Steps({ claim, now }: { claim: Claim; now: number | undefined }) {
  const resolved = ['Approved', 'Rejected', 'Expired'].includes(claim.status)
  const disputed = claim.status === 'Disputed' || claim.disputer !== ZERO
  const left = (t: number) => (now !== undefined && now < t ? `quedan ${formatDuration(t - now)}` : 'plazo cumplido')

  const steps = [
    { title: 'Reportado', done: true, current: false, text: 'Fianza depositada · pool congelado' },
    {
      title: 'Ventana de disputa',
      done: claim.status !== 'Pending',
      current: claim.status === 'Pending',
      text: claim.status === 'Pending' ? `Cierra ${formatDate(claim.disputeDeadline)} · ${left(claim.disputeDeadline)}` : disputed ? 'Alguien lo disputó' : 'Nadie lo disputó',
    },
    {
      title: 'Arbitraje',
      done: resolved && disputed,
      current: claim.status === 'Disputed',
      text: claim.status === 'Disputed' ? `Límite ${formatDate(claim.arbitrationDeadline)} · ${left(claim.arbitrationDeadline)}` : disputed ? 'Decidido' : 'No hizo falta',
    },
    {
      title: 'Resuelto',
      done: resolved,
      current: false,
      text: claim.status === 'Approved' ? `Recortados ${formatToken(claim.slashedAmount)} STK` : claim.status === 'Rejected' ? 'Sin recorte' : claim.status === 'Expired' ? 'Árbitro sin respuesta: sin recorte' : 'Pool descongelado al terminar',
    },
  ]

  return (
    <section aria-label="Fases del claim" className="card">
      <ol className="steps">
        {steps.map((s) => (
          <li key={s.title} className={`step ${s.done ? 'done' : ''} ${s.current ? 'current' : ''}`} aria-current={s.current ? 'step' : undefined}>
            <span className="step-dot">{s.done && <Check />}</span>
            <strong style={{ fontSize: 15 }}>{s.title}</strong>
            <span>{s.text}</span>
          </li>
        ))}
      </ol>
    </section>
  )
}

/** Panel de acciones: depende del estado del claim, de la hora y de quien eres. */
function Actions({ claim, now, user, arbiter, bond }: {
  claim: Claim
  now: number | undefined
  user: `0x${string}` | undefined
  arbiter: `0x${string}` | undefined
  bond: bigint
}) {
  const { claimManager, bondToken } = getDeployment()
  const tx = useTx()
  const [amount, setAmount] = useState(() => formatToken(claim.requestedAmount).replace(/\./g, ''))
  const { data: allowance } = useReadContract({
    address: bondToken,
    abi: mockERC20Abi,
    functionName: 'allowance',
    args: [user ?? ZERO, claimManager],
    query: { enabled: Boolean(user) },
  })

  const cm = { address: claimManager, abi: claimManagerAbi } as const
  const busy = tx.pending !== null
  const isArbiter = Boolean(user && arbiter && user.toLowerCase() === arbiter.toLowerCase())
  const disputeOpen = claim.status === 'Pending' && now !== undefined && now <= claim.disputeDeadline
  const canFinalize = claim.status === 'Pending' && now !== undefined && now > claim.disputeDeadline
  const canExpire = claim.status === 'Disputed' && now !== undefined && now > claim.arbitrationDeadline

  const dispute = () => {
    const call = { ...cm, functionName: 'dispute', args: [claim.id] } as const
    return (allowance ?? 0n) < bond
      ? tx.run('dispute', { address: bondToken, abi: mockERC20Abi, functionName: 'approve', args: [claimManager, bond] }, call)
      : tx.run('dispute', call)
  }

  function resolve(valid: boolean) {
    let wei = 0n
    if (valid) {
      try { wei = parseUnits(amount.replace(/\./g, '').replace(',', '.'), 18) } catch { return }
    }
    tx.run(valid ? 'approve' : 'reject', { ...cm, functionName: 'resolveDispute', args: [claim.id, valid, wei] })
  }

  if (['Approved', 'Rejected', 'Expired'].includes(claim.status)) {
    return (
      <section className="card compact" style={{ gap: 10 }}>
        <h2>Claim cerrado</h2>
        <p style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--ink-2)' }}>
          {claim.status === 'Approved' && `Se recortaron ${formatToken(claim.slashedAmount)} STK del pool y se enviaron a ${shortAddress(claim.recipient)}.`}
          {claim.status === 'Rejected' && 'El árbitro consideró que el exploit no era real. Quien disputó se llevó las dos fianzas.'}
          {claim.status === 'Expired' && 'El árbitro no respondió a tiempo. Se devolvieron las dos fianzas y no hubo recorte.'}
          {' '}El pool vuelve a estar activo.
        </p>
        <Link href={`/pool/${claim.pool}`} className="btn btn-secondary">Ir al pool</Link>
      </section>
    )
  }

  return (
    <>
      {tx.error && <p className="error" role="alert">{tx.error}</p>}

      {disputeOpen && (
        <section aria-label="Disputar" className="card dark compact">
          <h2>¿El exploit no es real?</h2>
          <p style={{ fontSize: 14, lineHeight: 1.55, color: 'var(--dark-muted)' }}>
            Disputar deposita una fianza igual a la del reportante y pasa la decisión al árbitro. Si el exploit es real, perderás la fianza.
          </p>
          <div className="row" style={{ borderColor: 'var(--dark-line)', color: 'var(--bg)' }}>
            <span style={{ color: 'var(--dark-muted)' }}>Tu fianza</span><span className="mono">{formatToken(bond)} BND</span>
          </div>
          <button type="button" className="btn btn-light" disabled={!user || busy} onClick={dispute}>
            {tx.pending === 'dispute' ? 'Enviando…' : !user ? 'Conecta tu wallet' : (allowance ?? 0n) < bond ? 'Aprobar y disputar' : 'Disputar'}
          </button>
        </section>
      )}

      {claim.status === 'Pending' && (
        <section aria-label="Finalizar" className="card compact" style={{ gap: 10 }}>
          <h2>Finalizar</h2>
          <p style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--ink-2)' }}>
            Si nadie disputa antes del {formatDate(claim.disputeDeadline)}, cualquiera puede ejecutar el claim: se recorta el stake y el reportante recupera su fianza.
          </p>
          <button type="button" className="btn btn-primary" disabled={!user || !canFinalize || busy}
            onClick={() => tx.run('finalize', { ...cm, functionName: 'finalizeUndisputed', args: [claim.id] })}>
            {tx.pending === 'finalize' ? 'Ejecutando…' : canFinalize ? 'Finalizar claim' : now !== undefined ? `Disponible en ${formatDuration(claim.disputeDeadline - now + 1)}` : 'Finalizar claim'}
          </button>
        </section>
      )}

      {claim.status === 'Disputed' && isArbiter && (
        <section aria-label="Arbitraje" className="card compact alert">
          <h2>Panel del árbitro</h2>
          <p style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--ink-2)' }}>
            Eres el árbitro de este protocolo. Revisa la evidencia y decide. Puedes recortar menos de lo pedido, nunca más.
          </p>
          <div className="field">
            <label htmlFor="arb-amount">Cantidad a recortar si es válido (STK)</label>
            <input id="arb-amount" className="input" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </div>
          <div className="btn-row">
            <button type="button" className="btn btn-dark" disabled={busy} onClick={() => resolve(true)}>
              {tx.pending === 'approve' ? 'Enviando…' : 'Exploit real: aprobar'}
            </button>
            <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => resolve(false)}>
              {tx.pending === 'reject' ? 'Enviando…' : 'Falso: rechazar'}
            </button>
          </div>
        </section>
      )}

      {claim.status === 'Disputed' && (
        <section aria-label="Expirar" className="card compact" style={{ gap: 10 }}>
          <h2>Si el árbitro no responde</h2>
          <p style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--ink-2)' }}>
            Pasado el {formatDate(claim.arbitrationDeadline)}, cualquiera puede cerrar el claim: se devuelven las dos fianzas y el pool se descongela sin recorte.
          </p>
          <button type="button" className="btn btn-secondary" disabled={!user || !canExpire || busy}
            onClick={() => tx.run('expire', { ...cm, functionName: 'expireDispute', args: [claim.id] })}>
            {tx.pending === 'expire' ? 'Enviando…' : canExpire ? 'Cerrar por expiración' : now !== undefined ? `Disponible en ${formatDuration(claim.arbitrationDeadline - now + 1)}` : 'Cerrar'}
          </button>
        </section>
      )}
    </>
  )
}

export function ClaimView({ id }: { id: bigint }) {
  const { address: user } = useConnection()
  const { claim, arbiter, bondAmount, loaded } = useClaim(id)
  const { pools } = usePools()
  const { now } = useChainTime(1000)

  if (!loaded) return <main className="container"><p className="muted">Cargando claim…</p></main>
  if (!claim) {
    return (
      <main className="container">
        <h1 style={{ fontSize: 32 }}>El claim #{id.toString()} no existe</h1>
        <Link href="/claims" className="btn btn-secondary" style={{ alignSelf: 'flex-start' }}>Ver todos los claims</Link>
      </main>
    )
  }

  const pool = pools?.find((p) => p.address === claim.pool)
  const cap = pool ? (pool.totalAssets * BigInt(pool.maxSlashBps)) / 10000n : undefined

  return (
    <main className="container">
      <nav aria-label="Ruta" style={{ fontSize: 14, color: 'var(--muted)', display: 'flex', gap: 8 }}>
        <Link href="/claims" style={{ color: 'var(--muted)' }}>Claims</Link>
        <span aria-hidden="true">/</span>
        <span style={{ color: 'var(--ink)' }}>#{id.toString()}</span>
      </nav>

      <section style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, flexWrap: 'wrap' }}>
          <h1 style={{ fontSize: 40, lineHeight: 1.1, letterSpacing: '-0.02em' }}>
            Claim #{id.toString()} · <Link href={`/pool/${claim.pool}`} style={{ color: 'var(--ink)' }}>{pool?.name ?? shortAddress(claim.pool)}</Link>
          </h1>
          <ClaimStatusChip status={claim.status} />
        </div>
        <p style={{ fontSize: 15, color: 'var(--ink-2)' }}>
          Reportado por <span className="mono" style={{ color: 'var(--ink)' }}>{shortAddress(claim.reporter)}</span>
          {user && user.toLowerCase() === claim.reporter.toLowerCase() && ' (tú)'}
        </p>
      </section>

      <Steps claim={claim} now={now} />

      <div className="two-col">
        <div className="col-main">
          <section aria-label="Detalles" className="card" style={{ gap: 4 }}>
            <h2 style={{ marginBottom: 12 }}>Detalles</h2>
            <div className="row"><span className="muted">Cantidad pedida</span><span className="mono">{formatToken(claim.requestedAmount)} STK</span></div>
            {claim.status === 'Approved' && (
              <div className="row"><span className="muted">Recortado</span><span className="mono" style={{ color: 'var(--alert)' }}>{formatToken(claim.slashedAmount)} STK</span></div>
            )}
            {cap !== undefined && claim.status !== 'Approved' && (
              <div className="row"><span className="muted">Recortable como máximo</span><span className="mono">{formatToken(cap)} STK ({(pool?.maxSlashBps ?? 0) / 100}%)</span></div>
            )}
            <div className="row"><span className="muted">Destino de la compensación</span><span className="mono">{shortAddress(claim.recipient)}</span></div>
            <div className="row"><span className="muted">Fianza por parte</span><span className="mono">{formatToken(bondAmount)} BND</span></div>
            {claim.disputer !== ZERO && (
              <div className="row"><span className="muted">Disputado por</span><span className="mono">{shortAddress(claim.disputer)}</span></div>
            )}
            <div className="row"><span className="muted">Evidencia</span><span className="mono" style={{ wordBreak: 'break-all' }}>{claim.evidenceURI}</span></div>
          </section>

          <section aria-label="Fianzas" className="card">
            <h2>Qué pasa con las fianzas</h2>
            <div className="stats" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 16 }}>
              {[
                ['Nadie disputa', 'Se recorta el stake y el reportante recupera su fianza.'],
                ['El árbitro lo aprueba', 'El reportante se lleva las dos fianzas. Quien disputó pierde la suya.'],
                ['El árbitro lo rechaza', 'No hay recorte. Quien disputó se lleva las dos fianzas.'],
              ].map(([t, d]) => (
                <div key={t} style={{ display: 'flex', flexDirection: 'column', gap: 6, padding: 16, borderRadius: 8, background: 'var(--bg)' }}>
                  <strong style={{ fontSize: 15 }}>{t}</strong>
                  <span style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--ink-2)' }}>{d}</span>
                </div>
              ))}
            </div>
          </section>
        </div>

        <aside className="col-side">
          <Actions claim={claim} now={now} user={user} arbiter={arbiter} bond={bondAmount} />
        </aside>
      </div>
    </main>
  )
}
