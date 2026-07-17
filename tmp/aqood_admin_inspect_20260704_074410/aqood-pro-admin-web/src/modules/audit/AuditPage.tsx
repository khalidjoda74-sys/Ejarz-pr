import { ColumnDef } from '@tanstack/react-table';
import { useMemo, useState } from 'react';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';
import { Field, Input, Select } from '@/components/ui/Field';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listAuditLogs } from '@/services/auditService';
import { AuditLog } from '@/types/audit';
import { safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { exportCsv } from '@/lib/csv';

export function AuditPage() {
  const { data, loading, error, refresh } = useFirestoreQuery(() => listAuditLogs(180), []);
  const [search, setSearch] = useState('');
  const [entity, setEntity] = useState('all');
  const rows = useMemo(() => (data ?? []).filter((log) => {
    const q = search.toLowerCase();
    const matchSearch = !q || [log.action, log.actorEmail, log.actorName, log.entityId, log.message].join(' ').toLowerCase().includes(q);
    const matchEntity = entity === 'all' || log.entityType === entity;
    return matchSearch && matchEntity;
  }).sort((a, b) => String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? ''))), [data, search, entity]);
  const entities = Array.from(new Set((data ?? []).map((log) => log.entityType).filter(Boolean)));
  const columns = useMemo<ColumnDef<AuditLog>[]>(() => [
    { accessorKey: 'action', header: 'العملية', cell: ({ row }) => <strong>{safeText(row.original.action)}</strong> },
    { accessorKey: 'entityType', header: 'النوع', cell: ({ row }) => <Badge tone="gold">{safeText(row.original.entityType)}</Badge> },
    { accessorKey: 'actorEmail', header: 'الأدمن', cell: ({ row }) => safeText(row.original.actorName || row.original.actorEmail) },
    { accessorKey: 'entityId', header: 'ID', cell: ({ row }) => safeText(row.original.entityId) },
    { accessorKey: 'createdAt', header: 'التاريخ', cell: ({ row }) => formatDate(row.original.createdAt) },
  ], []);
  return <div className="stack"><PageHeader title="سجل العمليات" subtitle="Audit logs لكل العمليات الحساسة في اللوحة." actions={<><Button variant="soft" onClick={refresh}>تحديث</Button><Button variant="gold" onClick={() => exportCsv('audit-logs.csv', rows)}>تصدير CSV</Button></>} />
    <div className="card" style={{ padding:14 }}><div className="filters-bar" style={{ gridTemplateColumns:'2fr 1fr' }}><Field label="بحث"><Input value={search} onChange={(e)=>setSearch(e.target.value)} placeholder="عملية، أدمن، ID..." /></Field><Field label="النوع"><Select value={entity} onChange={(e)=>setEntity(e.target.value)}><option value="all">كل الأنواع</option>{entities.map((item)=><option key={item} value={item}>{item}</option>)}</Select></Field></div></div>
    {loading && <TableSkeleton />}{error && <ErrorState message={error} onRetry={refresh} />}{!loading && !error && <DataGrid data={rows} columns={columns} mobileTitle={(r) => safeText(r.action)} mobileSubtitle={(r) => `${safeText(r.actorName || r.actorEmail)} · ${formatDate(r.createdAt)}`} mobileMeta={(r) => <Badge tone="gold">{safeText(r.entityType)}</Badge>} />}
  </div>;
}
