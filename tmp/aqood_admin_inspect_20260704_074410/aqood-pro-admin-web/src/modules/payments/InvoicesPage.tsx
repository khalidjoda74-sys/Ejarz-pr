import { ColumnDef } from '@tanstack/react-table';
import { useMemo } from 'react';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listInvoices } from '@/services/paymentService';
import { Invoice } from '@/types/payment';
import { formatCurrency, safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { exportCsv } from '@/lib/csv';

export function InvoicesPage() {
  const { data, loading, error, refresh } = useFirestoreQuery(() => listInvoices(120), []);
  const rows = data ?? [];
  const columns = useMemo<ColumnDef<Invoice>[]>(() => [
    { accessorKey: 'invoiceNumber', header: 'رقم الفاتورة', cell: ({ row }) => safeText(row.original.invoiceNumber || row.original.id) },
    { accessorKey: 'contractId', header: 'العقد', cell: ({ row }) => safeText(row.original.contractId) },
    { accessorKey: 'amount', header: 'المبلغ', cell: ({ row }) => formatCurrency(row.original.amount) },
    { accessorKey: 'status', header: 'الحالة', cell: ({ row }) => <Badge tone="gold">{safeText(row.original.status)}</Badge> },
    { accessorKey: 'createdAt', header: 'التاريخ', cell: ({ row }) => formatDate(row.original.createdAt) },
  ], []);
  return <div className="stack"><PageHeader title="الفواتير" subtitle="هيكل فواتير جاهز للتوسع وربطه بالعقود." actions={<><Button variant="soft" onClick={refresh}>تحديث</Button><Button variant="gold" onClick={() => exportCsv('invoices.csv', rows)}>تصدير CSV</Button></>} />
  {loading && <TableSkeleton />}{error && <ErrorState message={error} onRetry={refresh} />}{!loading && !error && <DataGrid data={rows} columns={columns} mobileTitle={(r) => safeText(r.invoiceNumber || r.id)} mobileSubtitle={(r) => `${formatCurrency(r.amount)} · ${safeText(r.status)}`} />}</div>;
}
