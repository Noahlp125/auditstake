import { formatUnits } from 'viem'

const es = (min: number, max: number) =>
  new Intl.NumberFormat('es-ES', { minimumFractionDigits: min, maximumFractionDigits: max })

/** 1234567890000000000000n -> "1.234,57" */
export function formatToken(value: bigint | undefined, decimals = 2): string {
  if (value === undefined) return '—'
  return es(decimals, decimals).format(Number(formatUnits(value, 18)))
}

/** Igual que formatToken pero desde un number ya en unidades (no wei). */
export function formatNumber(value: number, decimals = 2): string {
  return es(decimals, decimals).format(value)
}

/** 0xf39Fd6e5...2266 -> "0xf39f…2266" */
export function shortAddress(address: string | undefined): string {
  if (!address) return '—'
  return `${address.slice(0, 6)}…${address.slice(-4)}`
}

/** Segundos -> "3d 14h", "7d", "5h 20m", "45s" */
export function formatDuration(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds))
  const d = Math.floor(s / 86400)
  const h = Math.floor((s % 86400) / 3600)
  const m = Math.floor((s % 3600) / 60)
  const parts =
    d > 0 ? [[d, 'd'], [h, 'h']] : h > 0 ? [[h, 'h'], [m, 'm']] : m > 0 ? [[m, 'm'], [s % 60, 's']] : [[s, 's']]
  // Quita la segunda parte si es 0: "7d 0h" -> "7d"
  const shown = parts.length > 1 && parts[1][0] === 0 ? [parts[0]] : parts
  return shown.map(([n, u]) => `${n}${u}`).join(' ')
}

/** Timestamp (segundos) -> "13 oct, 18:40" */
export function formatDate(seconds: number): string {
  return new Intl.DateTimeFormat('es-ES', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(seconds * 1000))
}

/** Saca un mensaje legible de un error de wagmi/viem. */
export function errorMessage(error: unknown): string {
  if (!error) return ''
  const e = error as { shortMessage?: string; message?: string }
  return e.shortMessage ?? e.message ?? String(error)
}
