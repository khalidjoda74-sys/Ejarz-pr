import { ColumnDef } from '@tanstack/react-table';
import { useMemo, useState } from 'react';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';
import { Card } from '@/components/ui/Card';
import { Field, Select } from '@/components/ui/Field';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listInvoices } from '@/services/paymentService';
import { Invoice } from '@/types/payment';
import { formatCurrency, safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { exportCsv } from '@/lib/csv';

export function InvoicesPage() {
  const [filter, setFilter] = useState<'all' | 'paid' | 'pending' | 'failed' | 'demo'>('all');
  const { data, loading, error, refresh } = useFirestoreQuery(() => listInvoices(120), []);
  const allRows = data ?? [];
  const rows = useMemo(() => allRows.filter((invoice) => {
    if (filter === 'all') return true;
    if (filter === 'demo') return invoice.isDemo === true;
    return invoice.status === filter;
  }), [allRows, filter]);
  const columns = useMemo<ColumnDef<Invoice>[]>(() => [
    { accessorKey: 'invoiceNumber', header: 'رقم الفاتورة', cell: ({ row }) => safeText(row.original.invoiceNumber || row.original.id) },
    { accessorKey: 'contractId', header: 'العقد', cell: ({ row }) => safeText(row.original.contractId) },
    { accessorKey: 'uid', header: 'UID', cell: ({ row }) => safeText(row.original.uid || row.original.userId) },
    { accessorKey: 'paymentId', header: 'Payment ID', cell: ({ row }) => safeText(row.original.paymentId) },
    { accessorKey: 'amount', header: 'المبلغ', cell: ({ row }) => formatCurrency(row.original.amount) },
    { accessorKey: 'isDemo', header: 'النوع', cell: ({ row }) => row.original.isDemo ? <Badge tone="gold">Demo Payment</Badge> : <Badge tone="gray">داخلي</Badge> },
    { accessorKey: 'status', header: 'الحالة', cell: ({ row }) => <InvoiceStatusBadge status={row.original.status} /> },
    { accessorKey: 'createdAt', header: 'التاريخ', cell: ({ row }) => formatDate(row.original.createdAt) },
  ], []);
  return <div className="stack"><PageHeader title="الفواتير" subtitle="فواتير داخلية معلقة وليست فواتير مزود دفع إنتاجي." actions={<><Button variant="soft" onClick={refresh}>تحديث</Button><Button variant="gold" onClick={() => exportCsv('invoices.csv', rows)}>تصدير CSV</Button></>} />
  <Card style={{ padding: 18 }} goldLine><h2 className="section-title">تنبيه</h2><p className="page-subtitle">الفاتورة توضح رسوم العقد المحفوظة حسب نوعه ومدته، شاملة رسوم منصة إيجار ودون مبلغ الإيجار. السكني: 299 ريال للسنة الأولى و125 لكل سنة إضافية؛ التجاري: 399 و400 ريال. تحتفظ العقود السابقة برسومها المسجلة. في وضع Demo لا تعتبر إيصال خصم فعلي.</p></Card>
  <Card style={{ padding: 14 }}>
    <Field label="تصفية الفواتير">
      <Select value={filter} onChange={(e) => setFilter(e.target.value as typeof filter)}>
        <option value="all">الكل</option>
        <option value="paid">paid</option>
        <option value="pending">pending</option>
        <option value="failed">failed</option>
        <option value="demo">demo</option>
      </Select>
    </Field>
  </Card>
  {loading && <TableSkeleton />}{error && <ErrorState message={error} onRetry={refresh} />}{!loading && !error && <DataGrid data={rows} columns={columns} mobileTitle={(r) => safeText(r.invoiceNumber || r.id)} mobileSubtitle={(r) => `${formatCurrency(r.amount)} · ${safeText(r.status)}`} mobileMeta={(r) => r.isDemo ? <Badge tone="gold">Demo</Badge> : undefined} />}</div>;
}

function InvoiceStatusBadge({ status }: { status?: string }) {
  const tone = status === 'paid' ? 'green' : status === 'failed' ? 'red' : 'gold';
  return <Badge tone={tone as any}>{safeText(status)}</Badge>;
}
