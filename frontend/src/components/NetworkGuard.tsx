import type { ReactNode } from 'react'
import { hasDeployment } from '@/lib/contracts'
import { NETWORK_LABEL, TARGET_CHAIN } from '@/lib/network'

/** Si la red elegida no tiene contratos, explica que hacer en vez de romper la pagina. */
export function NetworkGuard({ children }: { children: ReactNode }) {
  if (hasDeployment()) return children
  return (
    <main className="container" style={{ paddingTop: 80 }}>
      <h1 style={{ fontSize: 32 }}>No hay contratos en {NETWORK_LABEL}</h1>
      <p style={{ color: 'var(--ink-2)', maxWidth: 680, lineHeight: 1.55 }}>
        La app apunta a la red {TARGET_CHAIN.name} (id {TARGET_CHAIN.id}), pero no encuentra
        <span className="mono"> deployments/{TARGET_CHAIN.id}.json</span>. Lanza el script de despliegue en esa red
        y después <span className="mono">npm run sync</span>, o cambia <span className="mono">NEXT_PUBLIC_NETWORK</span> en
        <span className="mono"> .env.local</span>.
      </p>
    </main>
  )
}
