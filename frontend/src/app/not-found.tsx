import Link from 'next/link'

// Pagina 404 propia: sustituye a la de Next, que trae su propio modo oscuro
// y se "pegaba" al resto de la app al volver atras.
export default function NotFound() {
  return (
    <main className="container" style={{ paddingTop: 80 }}>
      <p className="mono muted" style={{ fontSize: 13 }}>Error 404</p>
      <h1 style={{ fontSize: 40, letterSpacing: '-0.02em' }}>Esta página no existe</h1>
      <p style={{ color: 'var(--ink-2)' }}>Puede que la dirección del pool o el número de claim no sean correctos.</p>
      <div className="btn-row">
        <Link href="/" className="btn btn-dark">Volver a Explorar</Link>
        <Link href="/claims" className="btn btn-secondary">Ver claims</Link>
      </div>
    </main>
  )
}
