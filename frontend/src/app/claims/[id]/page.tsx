import { Suspense } from 'react'
// Se pinta la pagina 404 directamente: llamar a notFound() dentro de <Suspense>
// obliga a React a rehacer la pagina en el navegador.
import NotFound from '@/app/not-found'
import { ClaimView } from '@/components/claims/ClaimView'

async function ClaimLoader({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  if (!/^\d+$/.test(id) || id === '0') return <NotFound />
  return <ClaimView id={BigInt(id)} />
}

export default function Page({ params }: { params: Promise<{ id: string }> }) {
  return (
    <Suspense fallback={<main className="container"><p className="muted">Cargando claim…</p></main>}>
      <ClaimLoader params={params} />
    </Suspense>
  )
}
