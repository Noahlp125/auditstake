import { STATUS_LABEL, type ClaimStatus } from '@/hooks/useClaims'

const CLASS: Record<ClaimStatus, string> = {
  None: 'chip-muted',
  Pending: 'chip-frozen',
  Disputed: 'chip-frozen',
  Approved: 'chip-done',
  Rejected: 'chip-muted',
  Expired: 'chip-muted',
}

export function ClaimStatusChip({ status }: { status: ClaimStatus }) {
  return <span className={`chip ${CLASS[status]}`}>{STATUS_LABEL[status]}</span>
}
