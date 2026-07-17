import { ColumnDef } from '@tanstack/react-table';
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select } from '@/components/ui/Field';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listContracts } from '@/services/contractService';
import { Contract, CONTRACT_STATUSES } from '@/types/contract';
import { formatCurrency, getRecordValue, safeText, statusLabel } from '@/lib/formatters';
import { formatDate, toDate } from '@/lib/dates';
import { exportCsv } from '@/lib/csv';

export function ContractsPage() {
  const { data, loading, error, refresh } = useFirestoreQuery(() => listContracts(180), []);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('all');
  const [city, setCity] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return (data ?? []).filter((contract) => {
      const matchSearch = !q || [
        contract.id,
        contract.orderNumber,
        contract.customerName,
        contract.customerPhone,
        contract.customerEmail,
        contract.city,
        getRecordValue(contract.landlord, ['name', 'fullName', 'phone'], ''),
        getRecordValue(contract.tenant, ['name', 'fullName', 'phone'], ''),
        getRecordValue(contract.property, ['title', 'city', 'district'], ''),
      ].join(' ').toLowerCase().includes(q);
      const matchStatus = status === 'all' || contract.status === status;
      const matchCity = !city || String(contract.city ?? getRecordValue(contract.property, ['city'], '')).toLowerCase().includes(city.toLowerCase());
      const created = toDate(contract.createdAt);
      const matchFrom = !from || !created || created >= new Date(from);
      const matchTo = !to || !created || created <= new Date(`${to}T23:59:59`);
      return matchSearch && matchStatus && matchCity && matchFrom && matchTo;
    });
  }, [data, search, status, city, from, to]);

  const columns = useMemo<ColumnDef<Contract>[]>(() => [
    { accessorKey: 'orderNumber', header: 'رقم الطلب', cell: ({ row }) => <Link to={`/contracts/${row.original.id}`} style={{ fontWeight: 850 }}>{safeText(row.original.orderNumber || row.original.id)}</Link> },
    { accessorKey: 'customerName', header: 'العميل', cell: ({ row }) => <div><strong>{safeText(row.original.customerName)}</strong><div className="page-subtitle" style={{ margin: 0 }}>{safeText(row.original.customerPhone, '')}</div></div> },
    { accessorKey: 'status', header: 'الحالة', cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { accessorKey: 'contractType', header: 'نوع العقد', cell: ({ row }) => safeText(row.original.contractType) },
    { accessorKey: 'city', header: 'المدينة', cell: ({ row }) => safeText(row.original.city || getRecordValue(row.original.property, ['city'], '')) },
    { accessorKey: 'totalPayable', header: 'المبلغ', cell: ({ row }) => formatCurrency(row.original.totalPayable ?? row.original.totalFees ?? 398) },
    { accessorKey: 'createdAt', header: 'التاريخ', cell: ({ row }) => formatDate(row.original.createdAt) },
    { id: 'actions', header: 'فتح', cell: ({ row }) => <Link to={`/contracts/${row.original.id}`}><Button variant="soft">تفاصيل</Button></Link> },
  ], []);

  function exportRows() {
    exportCsv('contracts.csv', filtered.map((contract) => ({
      id: contract.id,
      orderNumber: contract.orderNumber,
      customerName: contract.customerName,
      customerPhone: contract.customerPhone,
      status: statusLabel(contract.status),
      city: contract.city,
      totalPayable: contract.totalPayable ?? contract.totalFees ?? 398,
      createdAt: formatDate(contract.createdAt),
    })));
  }

  return <div className="stack">
    <PageHeader title="إدارة العقود" subtitle="بحث وفلترة ومتابعة دورة العقد كاملة." actions={<><Button variant="soft" onClick={refresh}>تحديث</Button><Button variant="gold" onClick={exportRows} disabled={!filtered.length}>تصدير CSV</Button></>} />
    <div className="card" style={{ padding: 14 }}>
      <div className="filters-bar">
        <Field label="بحث"><Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="رقم الطلب، العميل، الجوال..." /></Field>
        <Field label="الحالة"><Select value={status} onChange={(e) => setStatus(e.target.value)}><option value="all">كل الحالات</option>{CONTRACT_STATUSES.map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}</Select></Field>
        <Field label="المدينة"><Input value={city} onChange={(e) => setCity(e.target.value)} placeholder="الرياض، جدة..." /></Field>
        <Field label="من تاريخ"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="إلى تاريخ"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
      </div>
      <Badge tone="navy">{filtered.length} عقد مطابق</Badge>
    </div>
    {loading && <TableSkeleton />}
    {error && <ErrorState message={error} onRetry={refresh} />}
    {!loading && !error && <DataGrid
      data={filtered}
      columns={columns}
      mobileTitle={(row) => row.orderNumber || row.id}
      mobileSubtitle={(row) => `${safeText(row.customerName)} · ${safeText(row.customerPhone, '')}`}
      mobileMeta={(row) => <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}><StatusBadge status={row.status} /><Badge tone="gold">{formatCurrency(row.totalPayable ?? row.totalFees ?? 398)}</Badge><Badge tone="gray">{formatDate(row.createdAt)}</Badge></div>}
      mobileActions={(row) => <Link to={`/contracts/${row.id}`}><Button variant="soft">فتح</Button></Link>}
    />}
  </div>;
}
