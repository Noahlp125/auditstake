'use client'

import { useReadContract, useReadContracts } from 'wagmi'
import { coveragePoolAbi, coverageRegistryAbi, getDeployment } from '@/lib/contracts'

const POOL_FIELDS = [
  'name',
  'totalAssets',
  'frozen',
  'rewardRate',
  'periodFinish',
  'maxSlashBps',
  'cooldownPeriod',
  'unstakeWindow',
] as const

export type PoolSummary = {
  address: `0x${string}`
  name: string
  protocol: `0x${string}`
  totalAssets: bigint
  frozen: boolean
  rewardRate: bigint
  periodFinish: bigint
  maxSlashBps: number
  cooldownPeriod: bigint
  unstakeWindow: bigint
}

/** Lista de pools del registry con sus datos principales. */
export function usePools() {
  const { registry } = getDeployment()

  const { data: pools, isLoading: loadingList, error: listError } = useReadContract({
    address: registry,
    abi: coverageRegistryAbi,
    functionName: 'allPools',
    query: { refetchInterval: 4000 },
  })

  const list = pools ?? []

  // Una lectura por campo y por pool, mas poolInfo del registry
  const { data, isLoading } = useReadContracts({
    contracts: list.flatMap((pool) => [
      ...POOL_FIELDS.map((functionName) => ({ address: pool, abi: coveragePoolAbi, functionName }) as const),
      { address: registry, abi: coverageRegistryAbi, functionName: 'poolInfo', args: [pool] } as const,
    ]),
    query: { enabled: list.length > 0, refetchInterval: 4000 },
  })

  const step = POOL_FIELDS.length + 1
  const summaries: PoolSummary[] | undefined = data
    ? list.map((address, i) => {
        const r = data.slice(i * step, (i + 1) * step).map((x) => x.result)
        const info = r[8] as readonly [`0x${string}`, `0x${string}`, bigint] | undefined
        return {
          address,
          name: String(r[0] ?? '').replace(/^AuditStake /, ''),
          totalAssets: (r[1] as bigint) ?? 0n,
          frozen: Boolean(r[2]),
          rewardRate: (r[3] as bigint) ?? 0n,
          periodFinish: (r[4] as bigint) ?? 0n,
          maxSlashBps: Number(r[5] ?? 0),
          cooldownPeriod: (r[6] as bigint) ?? 0n,
          unstakeWindow: (r[7] as bigint) ?? 0n,
          protocol: info?.[0] ?? '0x0000000000000000000000000000000000000000',
        }
      })
    : undefined

  return { pools: summaries, isLoading: loadingList || isLoading, error: listError }
}
