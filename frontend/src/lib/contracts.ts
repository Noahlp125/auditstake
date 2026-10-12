import { deployments } from '@/contracts/generated'
import { TARGET_CHAIN } from './network'

export {
  coveragePoolAbi,
  claimManagerAbi,
  coverageRegistryAbi,
  mockERC20Abi,
} from '@/contracts/generated'

type Deployment = {
  chainId: number
  deployer: `0x${string}`
  stakeToken: `0x${string}`
  premiumToken: `0x${string}`
  bondToken: `0x${string}`
  registry: `0x${string}`
  claimManager: `0x${string}`
  poolLumen: `0x${string}`
  poolOrbit: `0x${string}`
}

const all = deployments as unknown as Record<number, Deployment | undefined>

/** ¿Hay contratos desplegados en esta red? */
export function hasDeployment(chainId: number = TARGET_CHAIN.id): boolean {
  return all[chainId] !== undefined
}

/** Direcciones desplegadas en la red a la que apunta la app. */
export function getDeployment(chainId: number = TARGET_CHAIN.id): Deployment {
  const d = all[chainId]
  if (!d) {
    throw new Error(
      `No hay contratos desplegados en la red ${chainId}. Lanza Deploy.s.sol y "npm run sync".`,
    )
  }
  return d
}
