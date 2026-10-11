/** Debe coincidir con PRECISION en CoveragePool.sol */
export const PRECISION = 10n ** 36n
export const YEAR = 365n * 24n * 3600n

/** Prima que reparte el pool en un ano al ritmo actual (wei de PRM). 0 si no hay prima en curso. */
export function annualPremium(rewardRate: bigint, periodFinish: bigint, now: number | undefined): bigint {
  if (now === undefined || BigInt(Math.floor(now)) >= periodFinish) return 0n
  return (rewardRate * YEAR) / PRECISION
}
