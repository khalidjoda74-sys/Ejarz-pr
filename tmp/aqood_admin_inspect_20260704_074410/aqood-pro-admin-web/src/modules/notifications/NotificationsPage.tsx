import { ColumnDef } from '@tanstack/react-table';
import { useMemo } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listNotifications } from '@/services/notificationService';
import { AppNotification } from '@/types/notification';
import { safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';

export function NotificationsPage() {
  const { data, loading, error, refresh } = useFirestoreQuery(() => listNotifications(160), []);
  const columns = useMemo<ColumnDef<AppNotification>[]>(() => [
    { accessorKey: 'title', header: 'العنوان', cell: ({ row }) => <div><strong>{safeText(row.original.title)}</strong><div className="page-subtitle" style={{ margin: 0 }}>{safeText(row.original.body)}</div></div> },
    { accessorKey: 'userId', header: 'المستخدم', cell: ({ row }) => safeText(row.original.userId) },
    { accessorKey: 'contractId', header: 'العقد', cell: ({ row }) => safeText(row.original.contractId) },
    { accessorKey: 'priority', header: 'الأولوية', cell: ({ row }) => <Badge tone={row.original.priority === 'high' ? 'red' : 'gold'}>{row.original.priority === 'high' ? 'عالية' : 'عادية'}</Badge> },
    { accessorKey: 'delivery', header: 'Push', cell: ({ row }) => <Badge tone="gray">{safeText(row.original.delivery?.pushStatus)}</Badge> },
    { accessorKey: 'createdAt', header: 'التاريخ', cell: ({ row }) => formatDate(row.original.createdAt) },
  ], []);
  const rows = data ?? [];
  return <div className="stack"><PageHeader title="الإشعارات" subtitle="إشعارات داخلية مرتبطة بالعميل أو العقد." actions={<><Button variant="soft" onClick={refresh}>تحديث</Button><Link to="/notifications/new"><Button variant="gold">إشعار جديد</Button></Link></>} />
  {loading && <TableSkeleton />}{error && <ErrorState message={error} onRetry={refresh} />}{!loading && !error && <DataGrid data={rows} columns={columns} mobileTitle={(r) => r.title} mobileSubtitle={(r) => safeText(r.body)} mobileMeta={(r) => <><Badge tone={r.priority === 'high' ? 'red' : 'gold'}>{r.priority === 'high' ? 'عالية' : 'عادية'}</Badge> <Badge tone="gray">{formatDate(r.createdAt)}</Badge></>} />}</div>;
}
