import { ColumnDef } from '@tanstack/react-table';
import { useMemo } from 'react';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listPayments } from '@/services/paymentService';
import { Payment } from '@/types/payment';
import { formatCurrency, safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { exportCsv } from '@/lib/csv';

export function PaymentsPage() {
  const { data, loading, error, refresh } = useFirestoreQuery(() => listPayments(120), []);
  const rows = data ?? [];
  const totals = useMemo(() => rows.reduce((acc, p) => ({ count: acc.count + 1, amount: acc.amount + Number(p.amount || 0), paid: acc.paid + (p.status === 'paid' ? Number(p.amount || 0) : 0) }), { count: 0, amount: 0, paid: 0 }), [rows]);
  const columns = useMemo<ColumnDef<Payment>[]>(() => [
    { accessorKey: 'contractId', header: 'العقد', cell: ({ row }) => safeText(row.original.contractId) },
    { accessorKey: 'userId', header: 'المستخدم', cell: ({ row }) => safeText(row.original.userId) },
    { accessorKey: 'amount', header: 'المبلغ', cell: ({ row }) => formatCurrency(row.original.amount) },
    { accessorKey: 'method', header: 'الطريقة', cell: ({ row }) => safeText(row.original.method) },
    { accessorKey: 'status', header: 'الحالة', cell: ({ row }) => <PaymentBadge status={row.original.status} /> },
    { accessorKey: 'createdAt', header: 'التاريخ', cell: ({ row }) => formatDate(row.original.createdAt) },
  ], []);
  return <div className="stack"><PageHeader title="المدفوعات" subtitle="بنية مدفوعات جاهزة للربط بدون تنفيذ دفع حقيقي." actions={<><Button variant="soft" onClick={refresh}>تحديث</Button><Button variant="gold" onClick={() => exportCsv('payments.csv', rows)}>تصدير CSV</Button></>} />
    <div className="kpi-grid"><Kpi title="عدد المدفوعات" value={totals.count} /><Kpi title="إجمالي مسجل" value={formatCurrency(totals.amount)} /><Kpi title="المدفوع" value={formatCurrency(totals.paid)} /><Kpi title="رسوم العقد" value="398 ر.س" /></div>
    <Card style={{ padding: 18 }}><h2 className="section-title">طرق الدفع المدعومة كهيكل</h2><div style={{ display:'flex', gap:8, flexWrap:'wrap' }}><Badge tone="navy">mada</Badge><Badge tone="gold">applePay</Badge><Badge tone="green">bankTransfer</Badge></div></Card>
    {loading && <TableSkeleton />}{error && <ErrorState message={error} onRetry={refresh} />}{!loading && !error && <DataGrid data={rows} columns={columns} mobileTitle={(r) => safeText(r.contractId)} mobileSubtitle={(r) => `${safeText(r.method)} · ${formatCurrency(r.amount)}`} mobileMeta={(r) => <PaymentBadge status={r.status} />} />}
  </div>;
}
function Kpi({ title, value }: { title: string; value: React.ReactNode }) { return <Card className="kpi-card"><div className="kpi-label">{title}</div><div className="kpi-value">{value}</div></Card>; }
function PaymentBadge({ status }: { status?: string }) { const tone = status === 'paid' ? 'green' : status === 'failed' ? 'red' : status === 'refunded' ? 'orange' : 'gold'; return <Badge tone={tone as any}>{safeText(status)}</Badge>; }
