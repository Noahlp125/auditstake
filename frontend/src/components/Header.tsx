'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useBlockNumber } from 'wagmi'
import { ConnectButton } from './ConnectButton'
import { TimeWarp } from './TimeWarp'

function ShieldIcon() {
  return (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6l7-3z" />
      <path d="M9 12l2 2 4-4" />
    </svg>
  )
}

export function Header() {
  const pathname = usePathname()
  const { data: blockNumber, isError } = useBlockNumber({ watch: true })

  const links = [
    { href: '/', label: 'Explorar', active: pathname === '/' || pathname.startsWith('/pool') },
    { href: '/claims', label: 'Claims', active: pathname.startsWith('/claims') },
  ]

  return (
    <header className="header">
      <div className="header-inner">
        <div style={{ display: 'flex', alignItems: 'center', gap: 32, flexWrap: 'wrap' }}>
          <Link href="/" className="brand">
            <ShieldIcon />
            AuditStake
          </Link>
          <nav aria-label="Principal" className="nav">
            {links.map((l) => (
              <Link key={l.href} href={l.href} aria-current={l.active ? 'page' : undefined}>
                {l.label}
              </Link>
            ))}
          </nav>
        </div>
        <div className="header-right">
          <TimeWarp />
          <span className="pill" title={blockNumber ? `Bloque ${blockNumber}` : undefined}>
            <span className={`dot ${isError || !blockNumber ? 'off' : ''}`} />
            {isError ? 'Anvil no responde' : blockNumber ? `Anvil · bloque ${blockNumber}` : 'Conectando…'}
          </span>
          <ConnectButton />
        </div>
      </div>
    </header>
  )
}
