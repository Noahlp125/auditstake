'use client'

import { useReadContracts } from 'wagmi'
import { zeroAddress } from 'viem'
import {
  claimManagerAbi,
  coveragePoolAbi,
  coverageRegistryAbi,
  getDeployment,
  mockERC20Abi,
} from '@/lib/contracts'

const REFRESH_MS = 2000

/** Todo lo que la pantalla de un pool necesita leer, del pool y del usuario. */
export function usePool(pool: `0x${string}`, user: `0x${string}` | undefined) {
  const { registry, claimManager, stakeToken } = getDeployment()
  const who = user ?? zeroAddress
  const p = { address: pool, abi: coveragePoolAbi } as const

  const { data, isLoading, error } = useReadContracts({
    contracts: [
      { ...p, functionName: 'name' }, //                 0
      { ...p, functionName: 'totalAssets' }, //          1
      { ...p, functionName: 'totalSupply' }, //          2
      { ...p, functionName: 'rewardRate' }, //           3
      { ...p, functionName: 'periodFinish' }, //         4
      { ...p, functionName: 'frozen' }, //               5
      { ...p, functionName: 'maxSlashBps' }, //          6
      { ...p, functionName: 'cooldownPeriod' }, //       7
      { ...p, functionName: 'unstakeWindow' }, //        8
      { ...p, functionName: 'balanceOf', args: [who] }, // 9
      { ...p, functionName: 'earned', args: [who] }, //   10
      { ...p, functionName: 'cooldownStart', args: [who] }, // 11
      { ...p, functionName: 'maxRedeem', args: [who] }, // 12
      { address: stakeToken, abi: mockERC20Abi, functionName: 'balanceOf', args: [who] }, // 13
      { address: stakeToken, abi: mockERC20Abi, functionName: 'allowance', args: [who, pool] }, // 14
      { address: registry, abi: coverageRegistryAbi, functionName: 'poolInfo', args: [pool] }, // 15
      { address: claimManager, abi: claimManagerAbi, functionName: 'activeClaimOf', args: [pool] }, // 16
    ],
    query: { refetchInterval: REFRESH_MS },
  })

  const r = data?.map((x) => x.result)
  const shares = (r?.[9] as bigint | undefined) ?? 0n
  const totalAssets = (r?.[1] as bigint | undefined) ?? 0n
  const totalSupply = (r?.[2] as bigint | undefined) ?? 0n
  const info = r?.[15] as readonly [`0x${string}`, `0x${string}`, bigint] | undefined

  // Valor en STK de las shares del usuario (mismo calculo que convertToAssets, redondeando abajo)
  const userAssets = totalSupply > 0n ? (shares * totalAssets) / totalSupply : 0n

  return {
    isLoading,
    error,
    loaded: Boolean(r),
    name: String(r?.[0] ?? '').replace(/^AuditStake /, ''),
    totalAssets,
    totalSupply,
    rewardRate: (r?.[3] as bigint | undefined) ?? 0n,
    periodFinish: Number((r?.[4] as bigint | undefined) ?? 0n),
    frozen: Boolean(r?.[5]),
    maxSlashBps: Number(r?.[6] ?? 0),
    cooldownPeriod: Number((r?.[7] as bigint | undefined) ?? 0n),
    unstakeWindow: Number((r?.[8] as bigint | undefined) ?? 0n),
    shares,
    userAssets,
    earned: (r?.[10] as bigint | undefined) ?? 0n,
    cooldownStart: Number((r?.[11] as bigint | undefined) ?? 0n),
    maxRedeem: (r?.[12] as bigint | undefined) ?? 0n,
    walletBalance: (r?.[13] as bigint | undefined) ?? 0n,
    allowance: (r?.[14] as bigint | undefined) ?? 0n,
    protocol: info?.[0],
    sponsor: info?.[1],
    activeClaimId: (r?.[16] as bigint | undefined) ?? 0n,
  }
}

export type PoolData = ReturnType<typeof usePool>
