import type { Metadata } from 'next'
import { Suspense, type ReactNode } from 'react'
import { Providers } from './providers'
import { Header } from '@/components/Header'
import './globals.css'

export const metadata: Metadata = {
  title: 'AuditStake',
  description: 'Auditores que respaldan con su stake la seguridad de los protocolos',
}

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="es">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        {/* En el App Router el layout raiz se carga en todas las paginas: el aviso no aplica */}
        {/* eslint-disable-next-line @next/next/no-page-custom-font */}
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap"
        />
      </head>
      <body>
        <Providers>
          {/* La cabecera lee la URL (usePathname): va en Suspense para no bloquear el renderizado */}
          <Suspense fallback={<div className="header" style={{ height: 72 }} />}>
            <Header />
          </Suspense>
          {children}
        </Providers>
      </body>
    </html>
  )
}
