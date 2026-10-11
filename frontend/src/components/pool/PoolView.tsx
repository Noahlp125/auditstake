'use client'

import Link from 'next/link'
import { useConnection } from 'wagmi'
import { usePool } from '@/hooks/usePool'
import { useChainTime } from '@/hooks/useChainTime'
import { useTx } from '@/hooks/useTx'
import { errorMessage, shortAddress } from '@/lib/format'
import { StatusChip } from '@/components/ExploreView'
import { RewardsCard } from './RewardsCard'
import { PositionCard } from './PositionCard'
import { DepositCard } from './DepositCard'
import { PoolStats } from './PoolStats'
import { FrozenBanner } from './FrozenBanner'

export function PoolView({ address }: { address: `0x${string}` }) {
  const { address: user, isConnected } = useConnection()
  const data = usePool(address, user)
  const { now, blockTime } = useChainTime(250)
  const tx = useTx()

  if (data.error) {
    return <main className="container"><p className="error">No se pudo leer el pool: {errorMessage(data.error)}</p></main>
  }
  if (!data.loaded) {
    return <main className="container"><p className="muted">Cargando pool…</p></main>
  }

  return (
    <>
      {data.frozen && <FrozenBanner claimId={data.activeClaimId} now={now} />}

      <main className="container">
        <nav aria-label="Ruta" style={{ fontSize: 14, color: 'var(--muted)', display: 'flex', gap: 8 }}>
          <Link href="/" style={{ color: 'var(--muted)' }}>Explorar</Link>
          <span aria-hidden="true">/</span>
          <span style={{ color: 'var(--ink)' }}>{data.name}</span>
        </nav>

        <section style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, flexWrap: 'wrap' }}>
            <h1 style={{ fontSize: 40, lineHeight: 1.1, letterSpacing: '-0.02em' }}>{data.name}</h1>
            <StatusChip frozen={data.frozen} />
          </div>
          <span style={{ fontSize: 14, color: 'var(--muted)' }}>
            Contrato cubierto <span className="mono" style={{ color: 'var(--ink)' }}>{shortAddress(data.protocol)}</span>
            {' · '}Pool <span className="mono" style={{ color: 'var(--ink)' }}>{shortAddress(address)}</span>
          </span>
        </section>

        {!isConnected && (
          <p className="notice">Conecta una wallet (arriba a la derecha) para depositar y ver tu posición.</p>
        )}
        {tx.error && <p className="error" role="alert">{tx.error}</p>}

        <div className="two-col">
          <div className="col-main">
            <RewardsCard pool={address} data={data} now={now} blockTime={blockTime} tx={tx} connected={isConnected} />
            <PositionCard pool={address} user={user} data={data} now={now} tx={tx} />
          </div>
          <aside className="col-side">
            <DepositCard pool={address} user={user} data={data} tx={tx} />
            <PoolStats data={data} now={now} />
          </aside>
        </div>
      </main>
    </>
  )
}
