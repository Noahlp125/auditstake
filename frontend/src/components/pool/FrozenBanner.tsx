'use client'

import Link from 'next/link'
import { useReadContract } from 'wagmi'
import { claimManagerAbi, getDeployment } from '@/lib/contracts'
import { formatDuration } from '@/lib/format'

export function FrozenBanner({ claimId, now }: { claimId: bigint; now: number | undefined }) {
  const { claimManager } = getDeployment()
  const { data: claim } = useReadContract({
    address: claimManager,
    abi: claimManagerAbi,
    functionName: 'getClaim',
    args: [claimId],
  })

  const deadline = claim ? Number(claim.disputeDeadline) : undefined
  const disputed = claim?.status === 2

  return (
    <div role="alert" className="banner">
      <div className="banner-inner">
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
            strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" />
          </svg>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <strong style={{ fontSize: 17, fontWeight: 600 }}>Pool congelado: se ha reportado un exploit</strong>
            <span style={{ fontSize: 14 }}>
              Claim #{claimId.toString()}{' '}
              {disputed
                ? 'disputado, esperando al árbitro.'
                : deadline !== undefined && now !== undefined && now < deadline
                  ? `en ventana de disputa · quedan ${formatDuration(deadline - now)}.`
                  : 'listo para finalizar.'}{' '}
              Nadie puede depositar ni retirar hasta que se resuelva.
            </span>
          </div>
        </div>
        <Link href={`/claims/${claimId}`} className="btn btn-alert">Revisar el claim</Link>
      </div>
    </div>
  )
}
