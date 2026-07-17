import { ColumnDef } from '@tanstack/react-table';
import { useMemo, useState } from 'react';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Field, Select } from '@/components/ui/Field';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listPayments } from '@/services/paymentService';
import { Payment } from '@/types/payment';
import { formatCurrency, safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { exportCsv } from '@/lib/csv';

export function PaymentsPage() {
  const [filter, setFilter] = useState<'all' | 'paid' | 'pending' | 'failed' | 'demo'>('all');
  const { data, loading, error, refresh } = useFirestoreQuery(() => listPayments(120), []);
  const allRows = data ?? [];
  const rows = useMemo(() => allRows.filter((payment) => {
    if (filter === 'all') return true;
    if (filter === 'demo') return payment.isDemo === true || payment.provider === 'demo';
    return payment.status === filter;
  }), [allRows, filter]);
  const totals = useMemo(() => rows.reduce((acc, p) => ({ count: acc.count + 1, amount: acc.amount + Number(p.amount || 0), paid: acc.paid + (p.status === 'paid' ? Number(p.amount || 0) : 0) }), { count: 0, amount: 0, paid: 0 }), [rows]);
  const columns = useMemo<ColumnDef<Payment>[]>(() => [
    { accessorKey: 'contractId', header: 'العقد', cell: ({ row }) => safeText(row.original.contractId) },
    { accessorKey: 'uid', header: 'UID', cell: ({ row }) => safeText(row.original.uid || row.original.userId) },
    { accessorKey: 'amount', header: 'المبلغ', cell: ({ row }) => formatCurrency(row.original.amount) },
    { accessorKey: 'method', header: 'الطريقة', cell: ({ row }) => paymentMethodLabel(row.original.method) },
    { accessorKey: 'provider', header: 'المزود', cell: ({ row }) => <ProviderBadge provider={row.original.provider} isDemo={row.original.isDemo} /> },
    { accessorKey: 'providerReference', header: 'رقم العملية', cell: ({ row }) => safeText(row.original.providerReference || row.original.providerRef) },
    { accessorKey: 'cardLast4', header: 'البطاقة', cell: ({ row }) => cardLabel(row.original) },
    { accessorKey: 'status', header: 'الحالة', cell: ({ row }) => <PaymentBadge status={row.original.status} /> },
    { accessorKey: 'createdAt', header: 'التاريخ', cell: ({ row }) => formatDate(row.original.createdAt) },
  ], []);
  return <div className="stack"><PageHeader title="المدفوعات" subtitle="سجل مالي داخلي فقط. لا توجد بوابة دفع إنتاجية مربوطة حاليًا." actions={<><Button variant="soft" onClick={refresh}>تحديث</Button><Button variant="gold" onClick={() => exportCsv('payments.csv', rows)}>تصدير CSV</Button></>} />
    <div className="kpi-grid"><Kpi title="عدد المدفوعات" value={totals.count} /><Kpi title="إجمالي مسجل" value={formatCurrency(totals.amount)} /><Kpi title="المدفوع" value={formatCurrency(totals.paid)} /><Kpi title="رسوم العقد" value="398 ر.س" /></div>
    <Card style={{ padding: 18 }} goldLine><h2 className="section-title">تنبيه مالي</h2><p className="page-subtitle">هذه العمليات Demo فقط ولا تمثل خصمًا فعليًا. لا يتم تخزين رقم البطاقة الكامل أو CVV، وتظهر آخر 4 أرقام فقط عند توفرها.</p><div style={{ display:'flex', gap:8, flexWrap:'wrap' }}><Badge tone="gold">Demo Payment</Badge><Badge tone="navy">Mada</Badge><Badge tone="blue">Visa / Mastercard</Badge><Badge tone="green">Apple Pay Demo</Badge><Badge tone="purple">STC Pay Demo</Badge></div></Card>
    <Card style={{ padding: 14 }}>
      <Field label="تصفية المدفوعات">
        <Select value={filter} onChange={(e) => setFilter(e.target.value as typeof filter)}>
          <option value="all">الكل</option>
          <option value="paid">paid</option>
          <option value="pending">pending</option>
          <option value="failed">failed</option>
          <option value="demo">demo</option>
        </Select>
      </Field>
    </Card>
    {loading && <TableSkeleton />}{error && <ErrorState message={error} onRetry={refresh} />}{!loading && !error && <DataGrid data={rows} columns={columns} mobileTitle={(r) => safeText(r.contractId)} mobileSubtitle={(r) => `${paymentMethodLabel(r.method)} · ${formatCurrency(r.amount)}`} mobileMeta={(r) => <PaymentBadge status={r.status} />} />}
  </div>;
}
function Kpi({ title, value }: { title: string; value: React.ReactNode }) { return <Card className="kpi-card"><div className="kpi-label">{title}</div><div className="kpi-value">{value}</div></Card>; }
function PaymentBadge({ status }: { status?: string }) { const tone = status === 'paid' ? 'green' : status === 'failed' ? 'red' : status === 'refunded' ? 'orange' : 'gold'; return <Badge tone={tone as any}>{safeText(status)}</Badge>; }
function ProviderBadge({ provider, isDemo }: { provider?: string; isDemo?: boolean }) { return isDemo || provider === 'demo' ? <Badge tone="gold">Demo Payment</Badge> : <Badge tone="gray">{provider === 'notConfigured' ? 'غير مربوط' : safeText(provider)}</Badge>; }
function paymentMethodLabel(method?: string) {
  if (method === 'notSelected') return 'لم يحدد بعد';
  if (method === 'mada') return 'مدى';
  if (method === 'visaMastercard') return 'Visa / Mastercard';
  if (method === 'applePay') return 'Apple Pay - Demo';
  if (method === 'stcPay') return 'STC Pay - Demo';
  if (method === 'bankTransfer') return 'تحويل بنكي';
  return safeText(method);
}
function cardLabel(payment: Payment) {
  if (!payment.cardLast4) return 'غير متوفر';
  return `${safeText(payment.cardBrand, 'Card')} •••• ${payment.cardLast4}`;
}
