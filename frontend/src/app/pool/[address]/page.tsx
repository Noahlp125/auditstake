import { Suspense } from 'react'
import { isAddress } from 'viem'
// Se pinta la pagina 404 directamente: llamar a notFound() dentro de <Suspense>
// obliga a React a rehacer la pagina en el navegador.
import NotFound from '@/app/not-found'
import { PoolView } from '@/components/pool/PoolView'

// La direccion del pool solo se conoce al pedir la pagina, asi que se resuelve
// dentro de <Suspense> y el resto de la pagina se puede servir al instante.
async function PoolLoader({ params }: { params: Promise<{ address: string }> }) {
  const { address } = await params
  if (!isAddress(address)) return <NotFound />
  return <PoolView address={address} />
}

export default function Page({ params }: { params: Promise<{ address: string }> }) {
  return (
    <Suspense fallback={<main className="container"><p className="muted">Cargando pool…</p></main>}>
      <PoolLoader params={params} />
    </Suspense>
  )
}
