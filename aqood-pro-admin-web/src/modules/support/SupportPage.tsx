import { ColumnDef } from '@tanstack/react-table';
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';
import { Field, Select } from '@/components/ui/Field';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listSupportTickets } from '@/services/supportService';
import { SupportTicket } from '@/types/support';
import { safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';

const statusLabels: Record<string, string> = { open: 'مفتوحة', pending: 'بانتظار العميل', resolved: 'محلولة', closed: 'مغلقة' };

export function SupportPage() {
  const { data, loading, error, refresh } = useFirestoreQuery(() => listSupportTickets(160), []);
  const [status, setStatus] = useState('all');
  const rows = useMemo(() => (data ?? []).filter((ticket) => status === 'all' || ticket.status === status), [data, status]);
  const columns = useMemo<ColumnDef<SupportTicket>[]>(() => [
    { accessorKey: 'subject', header: 'الموضوع', cell: ({ row }) => <Link to={`/support/${row.original.id}`}><strong>{safeText(row.original.subject)}</strong><div className="page-subtitle" style={{ margin: 0 }}>{safeText(row.original.message, '')}</div></Link> },
    { accessorKey: 'status', header: 'الحالة', cell: ({ row }) => <SupportBadge status={row.original.status} /> },
    { accessorKey: 'priority', header: 'الأولوية', cell: ({ row }) => <Badge tone={row.original.priority === 'high' ? 'red' : 'gray'}>{row.original.priority === 'high' ? 'عالية' : 'عادية'}</Badge> },
    { accessorKey: 'uid', header: 'المستخدم', cell: ({ row }) => <><strong>{safeText(row.original.customerName || row.original.uid || row.original.userId)}</strong><div className="page-subtitle" style={{ margin: 0 }}>{safeText(row.original.customerPhone || row.original.uid || row.original.userId, '')}</div></> },
    { accessorKey: 'contractId', header: 'العقد', cell: ({ row }) => safeText(row.original.contractId) },
    { accessorKey: 'createdAt', header: 'التاريخ', cell: ({ row }) => formatDate(row.original.createdAt) },
    { id: 'actions', header: 'فتح', cell: ({ row }) => <Link to={`/support/${row.original.id}`}><Button variant="soft">فتح</Button></Link> },
  ], []);
  return <div className="stack"><PageHeader title="الدعم الفني" subtitle="إدارة تذاكر الدعم والردود وتغيير الحالة." actions={<Button variant="soft" onClick={refresh}>تحديث</Button>} />
    <div className="card" style={{ padding: 14, maxWidth: 340 }}><Field label="فلترة الحالة"><Select value={status} onChange={(e) => setStatus(e.target.value)}><option value="all">كل الحالات</option><option value="open">مفتوحة</option><option value="pending">بانتظار العميل</option><option value="resolved">محلولة</option><option value="closed">مغلقة</option></Select></Field></div>
    {loading && <TableSkeleton />}{error && <ErrorState message={error} onRetry={refresh} />}{!loading && !error && <DataGrid data={rows} columns={columns} mobileTitle={(r) => safeText(r.subject)} mobileSubtitle={(r) => safeText(r.message)} mobileMeta={(r) => <><SupportBadge status={r.status} /> <Badge tone="gray">{formatDate(r.createdAt)}</Badge></>} mobileActions={(r) => <Link to={`/support/${r.id}`}><Button variant="soft">فتح</Button></Link>} />}</div>;
}

export function SupportBadge({ status }: { status?: string }) {
  const tone = status === 'open' ? 'red' : status === 'pending' ? 'orange' : status === 'resolved' ? 'green' : 'gray';
  return <Badge tone={tone as any}>{statusLabels[status ?? ''] ?? safeText(status)}</Badge>;
}
