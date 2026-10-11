'use client'

import { useState } from 'react'
import { useReadContracts } from 'wagmi'
import { isAddress, parseUnits, zeroAddress } from 'viem'
import { useRouter } from 'next/navigation'
import { claimManagerAbi, getDeployment, mockERC20Abi } from '@/lib/contracts'
import { formatToken } from '@/lib/format'
import type { PoolSummary } from '@/hooks/usePools'
import type { useTx } from '@/hooks/useTx'

type Props = {
  pools: PoolSummary[]
  user: `0x${string}` | undefined
  tx: ReturnType<typeof useTx>
  nextId: bigint
}

/** Reportar un exploit: deposita la fianza y congela el pool al momento. */
export function SubmitClaimForm({ pools, user, tx, nextId }: Props) {
  const router = useRouter()
  const { claimManager, bondToken } = getDeployment()
  const available = pools.filter((p) => !p.frozen)

  const [pool, setPool] = useState<string>('')
  const [amount, setAmount] = useState('')
  const [recipient, setRecipient] = useState('')
  const [evidence, setEvidence] = useState('')

  const selected = available.find((p) => p.address === pool) ?? available[0]
  const to = (recipient || user || '') as `0x${string}`

  const { data } = useReadContracts({
    contracts: [
      { address: claimManager, abi: claimManagerAbi, functionName: 'bondAmount' },
      { address: bondToken, abi: mockERC20Abi, functionName: 'balanceOf', args: [user ?? zeroAddress] },
      { address: bondToken, abi: mockERC20Abi, functionName: 'allowance', args: [user ?? zeroAddress, claimManager] },
    ],
    query: { refetchInterval: 3000 },
  })
  const bond = (data?.[0]?.result as bigint | undefined) ?? 0n
  const bondBalance = (data?.[1]?.result as bigint | undefined) ?? 0n
  const allowance = (data?.[2]?.result as bigint | undefined) ?? 0n

  let wei: bigint | undefined
  try {
    wei = amount ? parseUnits(amount.replace(/\./g, '').replace(',', '.'), 18) : undefined
  } catch {
    wei = undefined
  }

  const problems = [
    !user && 'Conecta una wallet',
    !selected && 'No hay pools activos',
    (!wei || wei === 0n) && 'Indica la cantidad',
    !isAddress(to) && 'Destino no válido',
    user && bondBalance < bond && `Necesitas ${formatToken(bond)} BND de fianza`,
  ].filter(Boolean) as string[]

  async function submit() {
    if (!selected || !wei || !user) return
    const call = {
      address: claimManager,
      abi: claimManagerAbi,
      functionName: 'submitClaim',
      args: [selected.address, wei, to, evidence || 'sin evidencia'],
    } as const
    const ok =
      allowance < bond
        ? await tx.run('submit', { address: bondToken, abi: mockERC20Abi, functionName: 'approve', args: [claimManager, bond] }, call)
        : await tx.run('submit', call)
    if (ok) {
      // Next guarda el estado de las paginas visitadas: si no se vacia, al volver
      // aqui el formulario conservaria la cantidad del claim anterior.
      setPool('')
      setAmount('')
      setRecipient('')
      setEvidence('')
      router.push(`/claims/${nextId}`)
    }
  }

  const faucet = () =>
    user && tx.run('bond-faucet', { address: bondToken, abi: mockERC20Abi, functionName: 'mint', args: [user, parseUnits('100', 18)] })

  return (
    <section aria-label="Reportar un exploit" className="card compact">
      <h2>Reportar un exploit</h2>
      <p style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--ink-2)' }}>
        Depositas una fianza de <strong>{formatToken(bond)} BND</strong> y el pool se congela al instante. Si nadie
        lo disputa en 3 días, se recorta el stake y recuperas la fianza. Si te disputan y el árbitro te quita la razón, la pierdes.
      </p>

      <div className="field">
        <label htmlFor="claim-pool">Pool afectado</label>
        <select id="claim-pool" className="select" value={selected?.address ?? ''} onChange={(e) => setPool(e.target.value)}>
          {available.length === 0 && <option value="">Todos los pools tienen un claim abierto</option>}
          {available.map((p) => (
            <option key={p.address} value={p.address}>{p.name} · {formatToken(p.totalAssets, 0)} STK</option>
          ))}
        </select>
      </div>

      <div className="field">
        <label htmlFor="claim-amount">Cantidad a recortar (STK)</label>
        <input id="claim-amount" className="input" inputMode="decimal" placeholder="0,00" value={amount} onChange={(e) => setAmount(e.target.value)} />
        {selected && (
          <span style={{ fontSize: 13, color: 'var(--muted)' }}>
            Máximo recortable: {formatToken((selected.totalAssets * BigInt(selected.maxSlashBps)) / 10000n)} STK ({selected.maxSlashBps / 100}% del pool). Si pides más, se recorta el máximo.
          </span>
        )}
      </div>

      <div className="field">
        <label htmlFor="claim-to">Destino de la compensación</label>
        <input id="claim-to" className="input text" placeholder={user ?? '0x…'} value={recipient} onChange={(e) => setRecipient(e.target.value.trim())} />
        <span style={{ fontSize: 13, color: 'var(--muted)' }}>Vacío = tu propia dirección.</span>
      </div>

      <div className="field">
        <label htmlFor="claim-evidence">Evidencia</label>
        <input id="claim-evidence" className="input text" placeholder="ipfs://… o hash de la transacción del exploit" value={evidence} onChange={(e) => setEvidence(e.target.value)} />
      </div>

      {user && (
        <span style={{ fontSize: 13, color: 'var(--muted)', display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          Tienes <span className="mono">{formatToken(bondBalance)} BND</span>
          <button type="button" onClick={faucet} disabled={tx.pending !== null}
            style={{ font: 'inherit', fontSize: 13, color: 'var(--accent)', background: 'none', border: 0, padding: 0, cursor: 'pointer', textDecoration: 'underline' }}>
            Conseguir 100 BND de prueba
          </button>
        </span>
      )}

      <button type="button" className="btn btn-dark" disabled={problems.length > 0 || tx.pending !== null} onClick={submit}>
        {tx.pending === 'submit' ? 'Enviando…' : problems[0] ?? (allowance < bond ? 'Aprobar fianza y reportar' : 'Reportar exploit')}
      </button>
    </section>
  )
}
