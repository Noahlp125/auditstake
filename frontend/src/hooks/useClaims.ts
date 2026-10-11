'use client'

import { useReadContract, useReadContracts } from 'wagmi'
import { claimManagerAbi, getDeployment } from '@/lib/contracts'

/** Estados del enum Status de ClaimManager.sol, en el mismo orden. */
export const STATUS = ['None', 'Pending', 'Disputed', 'Approved', 'Rejected', 'Expired'] as const
export type ClaimStatus = (typeof STATUS)[number]

export const STATUS_LABEL: Record<ClaimStatus, string> = {
  None: '—',
  Pending: 'Ventana de disputa',
  Disputed: 'En arbitraje',
  Approved: 'Aprobado',
  Rejected: 'Rechazado',
  Expired: 'Expirado',
}

export type Claim = {
  id: bigint
  pool: `0x${string}`
  reporter: `0x${string}`
  disputer: `0x${string}`
  recipient: `0x${string}`
  requestedAmount: bigint
  slashedAmount: bigint
  disputeDeadline: number
  arbitrationDeadline: number
  status: ClaimStatus
  evidenceURI: string
}

type RawClaim = {
  pool: `0x${string}`
  reporter: `0x${string}`
  disputer: `0x${string}`
  recipient: `0x${string}`
  requestedAmount: bigint
  slashedAmount: bigint
  disputeDeadline: bigint
  arbitrationDeadline: bigint
  status: number
  evidenceURI: string
}

function toClaim(id: bigint, c: RawClaim): Claim {
  return {
    ...c,
    id,
    disputeDeadline: Number(c.disputeDeadline),
    arbitrationDeadline: Number(c.arbitrationDeadline),
    status: STATUS[c.status] ?? 'None',
  }
}

/** Todos los claims, del mas reciente al mas antiguo. */
export function useClaims() {
  const { claimManager } = getDeployment()
  const { data: count } = useReadContract({
    address: claimManager,
    abi: claimManagerAbi,
    functionName: 'claimCount',
    query: { refetchInterval: 3000 },
  })

  const ids = Array.from({ length: Number(count ?? 0n) }, (_, i) => BigInt(i + 1)).reverse()
  const { data } = useReadContracts({
    contracts: ids.map((id) => ({ address: claimManager, abi: claimManagerAbi, functionName: 'getClaim', args: [id] }) as const),
    query: { enabled: ids.length > 0, refetchInterval: 3000 },
  })

  const claims = data
    ? ids.flatMap((id, i) => (data[i]?.result ? [toClaim(id, data[i].result as RawClaim)] : []))
    : ids.length === 0 && count !== undefined
      ? []
      : undefined

  return { claims }
}

/** Un claim concreto y los datos fijos del ClaimManager (fianza, arbitro...). */
export function useClaim(id: bigint) {
  const { claimManager } = getDeployment()
  const cm = { address: claimManager, abi: claimManagerAbi } as const
  const { data } = useReadContracts({
    contracts: [
      { ...cm, functionName: 'getClaim', args: [id] },
      { ...cm, functionName: 'arbiter' },
      { ...cm, functionName: 'bondAmount' },
    ],
    query: { refetchInterval: 2000 },
  })

  const raw = data?.[0]?.result as RawClaim | undefined
  const exists = raw !== undefined && raw.status !== 0
  return {
    loaded: data !== undefined,
    claim: exists ? toClaim(id, raw) : undefined,
    arbiter: data?.[1]?.result as `0x${string}` | undefined,
    bondAmount: (data?.[2]?.result as bigint | undefined) ?? 0n,
  }
}
