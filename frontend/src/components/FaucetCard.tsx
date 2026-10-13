'use client'

import { useBalance, useConnection, useReadContracts } from 'wagmi'
import { parseEther } from 'viem'
import { getDeployment, mockERC20Abi } from '@/lib/contracts'
import { IS_LOCAL, TARGET_CHAIN } from '@/lib/network'
import { formatToken } from '@/lib/format'
import { useTx } from '@/hooks/useTx'

// Lo que da el faucet en cada uso: STK para hacer stake y BND para la fianza de un claim.
const STK_AMOUNT = parseEther('1000')
const BND_AMOUNT = parseEther('100')

/**
 * Faucet de tokens de prueba. Los MockERC20 tienen mint() publico, asi que cualquiera
 * puede acunarse tokens para probar la app. Solo tiene sentido en testnet/local.
 */
export function FaucetCard() {
  const { address, isConnected, chainId } = useConnection()
  const d = getDeployment()
  const tx = useTx()

  const { data: eth } = useBalance({ address, query: { enabled: !!address } })
  const { data } = useReadContracts({
    contracts: [
      { address: d.stakeToken, abi: mockERC20Abi, functionName: 'balanceOf', args: [address!] },
      { address: d.bondToken, abi: mockERC20Abi, functionName: 'balanceOf', args: [address!] },
    ],
    query: { enabled: !!address },
  })
  const stk = data?.[0]?.result as bigint | undefined
  const bnd = data?.[1]?.result as bigint | undefined

  if (!isConnected || chainId !== TARGET_CHAIN.id) return null

  const noGas = !IS_LOCAL && eth !== undefined && eth.value === 0n

  function mint() {
    tx.run(
      'mint',
      { address: d.stakeToken, abi: mockERC20Abi, functionName: 'mint', args: [address!, STK_AMOUNT] },
      { address: d.bondToken, abi: mockERC20Abi, functionName: 'mint', args: [address!, BND_AMOUNT] },
    )
  }

  return (
    <section className="card compact" aria-label="Tokens de prueba"
      style={{ flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 20 }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, flex: '1 1 320px' }}>
        <h2 style={{ fontSize: 18 }}>Tokens de prueba</h2>
        <p className="muted" style={{ fontSize: 14, lineHeight: 1.5 }}>
          Consigue {formatToken(STK_AMOUNT, 0)} STK para respaldar pools y {formatToken(BND_AMOUNT, 0)} BND para la
          fianza de un claim. Son tokens sin valor, solo para probar.
        </p>
        <p className="mono" style={{ fontSize: 13 }}>
          Tienes {formatToken(stk, 0)} STK · {formatToken(bnd, 0)} BND
        </p>
        {noGas && (
          <p className="notice" style={{ marginTop: 6 }}>
            Necesitas un poco de ETH de Sepolia para pagar el gas. Pídelo gratis en un faucet, por ejemplo{' '}
            <a href="https://cloud.google.com/application/web3/faucet/ethereum/sepolia" target="_blank" rel="noreferrer">
              el de Google Cloud
            </a>.
          </p>
        )}
        {tx.error && <p className="error" role="alert">{tx.error}</p>}
      </div>
      <button type="button" className="btn btn-primary" disabled={!!tx.pending || noGas} onClick={mint}>
        {tx.pending ? 'Firmando y esperando…' : 'Conseguir tokens'}
      </button>
    </section>
  )
}
