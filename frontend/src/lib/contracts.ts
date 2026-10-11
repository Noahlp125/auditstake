import { deployments } from '@/contracts/generated'
import { foundry } from 'wagmi/chains'

export {
  coveragePoolAbi,
  claimManagerAbi,
  coverageRegistryAbi,
  mockERC20Abi,
} from '@/contracts/generated'

type Deployment = (typeof deployments)[keyof typeof deployments]

/** Direcciones desplegadas en la red activa (de momento, Anvil). */
export function getDeployment(chainId: number = foundry.id): Deployment {
  const d = (deployments as Record<number, Deployment>)[chainId]
  if (!d) {
    throw new Error(
      `No hay contratos desplegados en la red ${chainId}. Lanza Deploy.s.sol y "npm run sync".`,
    )
  }
  return d
}
