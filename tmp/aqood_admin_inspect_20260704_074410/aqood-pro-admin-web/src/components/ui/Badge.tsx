import { clsx } from 'clsx';
import { CONTRACT_STATUS_LABELS, ContractStatus } from '@/types/contract';

const statusTone: Record<ContractStatus, string> = {
  draft: 'gray',
  awaitingPayment: 'orange',
  underReview: 'blue',
  missingData: 'red',
  readyForEjar: 'gold',
  enteredInEjar: 'purple',
  awaitingAuthentication: 'navy',
  authenticated: 'green',
  rejected: 'red',
};

export function Badge({ tone = 'gray', children }: { tone?: 'navy' | 'gold' | 'green' | 'red' | 'orange' | 'blue' | 'purple' | 'gray'; children: React.ReactNode }) {
  return <span className={clsx('badge', `badge-${tone}`)}>{children}</span>;
}

export function StatusBadge({ status }: { status?: string }) {
  const typed = status as ContractStatus;
  const label = CONTRACT_STATUS_LABELS[typed] ?? status ?? 'غير محدد';
  const tone = statusTone[typed] ?? 'gray';
  return <Badge tone={tone}>{label}</Badge>;
}

export function UserStatusBadge({ blocked, status }: { blocked?: boolean; status?: string }) {
  if (blocked || status === 'blocked') return <Badge tone="red">محظور</Badge>;
  if (status === 'suspended') return <Badge tone="orange">موقوف</Badge>;
  return <Badge tone="green">نشط</Badge>;
}
