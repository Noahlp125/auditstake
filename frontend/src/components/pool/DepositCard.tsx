'use client'

import { useState } from 'react'
import { parseUnits } from 'viem'
import { coveragePoolAbi, getDeployment, mockERC20Abi } from '@/lib/contracts'
import { formatNumber, formatToken } from '@/lib/format'
import type { PoolData } from '@/hooks/usePool'
import type { useTx } from '@/hooks/useTx'

type Props = {
  pool: `0x${string}`
  user: `0x${string}` | undefined
  data: PoolData
  tx: ReturnType<typeof useTx>
}

/** "1.234,5" o "1234.5" -> bigint en wei. Devuelve undefined si no es un numero valido. */
function parseAmount(text: string): bigint | undefined {
  const clean = text.trim().replace(/\./g, '').replace(',', '.')
  if (!/^\d+(\.\d{0,18})?$/.test(clean)) return undefined
  try {
    return parseUnits(clean, 18)
  } catch {
    return undefined
  }
}

export function DepositCard({ pool, user, data, tx }: Props) {
  const { stakeToken } = getDeployment()
  const [text, setText] = useState('')
  const amount = parseAmount(text)
  const { frozen, walletBalance, allowance, shares, totalSupply, totalAssets, cooldownStart } = data

  if (frozen) {
    return (
      <section aria-label="Depositar" className="card compact" style={{ gap: 10 }}>
        <h2>Depositar</h2>
        <p style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--ink-2)' }}>
          No se aceptan depósitos durante un claim: quien entrara ahora pagaría por un exploit que no respaldó.
        </p>
        <button type="button" className="btn" disabled>Depósitos en pausa</button>
      </section>
    )
  }

  // Parte del pool tras el deposito (aproximada: shares proporcionales a los activos)
  const userAssets = totalSupply > 0n ? (shares * totalAssets) / totalSupply : 0n
  const now = totalAssets > 0n ? Number((userAssets * 10000n) / totalAssets) / 100 : 0
  const after =
    amount && amount > 0n ? Number(((userAssets + amount) * 10000n) / (totalAssets + amount)) / 100 : now

  const tooMuch = amount !== undefined && amount > walletBalance
  const canDeposit = Boolean(user) && amount !== undefined && amount > 0n && !tooMuch && tx.pending === null

  async function deposit() {
    if (!user || !amount) return
    const deposit = { address: pool, abi: coveragePoolAbi, functionName: 'deposit', args: [amount, user] } as const
    // Si el pool aun no puede mover nuestros STK, primero approve y luego deposit
    const ok =
      allowance < amount
        ? await tx.run('deposit', { address: stakeToken, abi: mockERC20Abi, functionName: 'approve', args: [pool, amount] }, deposit)
        : await tx.run('deposit', deposit)
    if (ok) setText('')
  }

  // Solo en local: los tokens de prueba tienen mint() publico
  const faucet = () =>
    user &&
    tx.run('faucet', { address: stakeToken, abi: mockERC20Abi, functionName: 'mint', args: [user, parseUnits('1000', 18)] })

  return (
    <section aria-label="Depositar" className="card compact">
      <h2>Depositar</h2>
      <div className="field">
        <label htmlFor="amount">Cantidad de STK</label>
        <div className="input-row">
          <input
            id="amount"
            className="input"
            type="text"
            inputMode="decimal"
            placeholder="0,00"
            value={text}
            onChange={(e) => setText(e.target.value)}
            aria-invalid={tooMuch || (text !== '' && amount === undefined)}
          />
          <button type="button" className="btn btn-secondary" onClick={() => setText(formatToken(walletBalance).replace(/\./g, ''))}>
            Máx.
          </button>
        </div>
        <span style={{ fontSize: 13, color: 'var(--muted)', display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
          En tu cartera: <span className="mono">{formatToken(walletBalance)} STK</span>
          {user && (
            <button type="button" onClick={faucet} disabled={tx.pending !== null}
              style={{ font: 'inherit', fontSize: 13, color: 'var(--accent)', background: 'none', border: 0, padding: 0, cursor: 'pointer', textDecoration: 'underline' }}>
              {tx.pending === 'faucet' ? 'Pidiendo…' : 'Conseguir 1.000 STK de prueba'}
            </button>
          )}
        </span>
        {tooMuch && <span style={{ fontSize: 13, color: '#8a1c1c' }}>No tienes tantos STK.</span>}
      </div>

      <div className="row" style={{ borderTop: '1px solid var(--line-soft)' }}>
        <span className="muted">Tu parte del pool</span>
        <span className="mono">{formatNumber(now, 1)}% → {formatNumber(after, 1)}%</span>
      </div>

      {cooldownStart > 0 && (
        <div className="notice">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
            strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flex: '0 0 auto', marginTop: 1 }}>
            <circle cx="12" cy="12" r="9" /><path d="M12 8v5" /><path d="M12 16h.01" />
          </svg>
          <span>Depositar reinicia tu cooldown. Volverás a esperar desde cero para retirar.</span>
        </div>
      )}

      <button type="button" className="btn btn-primary" disabled={!canDeposit} onClick={deposit}>
        {tx.pending === 'deposit'
          ? 'Confirmando…'
          : !user
            ? 'Conecta tu wallet'
            : amount !== undefined && allowance < amount
              ? 'Aprobar y depositar'
              : 'Depositar'}
      </button>
    </section>
  )
}
