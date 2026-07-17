import { ColumnDef } from '@tanstack/react-table';
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select } from '@/components/ui/Field';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listProperties } from '@/services/propertyService';
import { Property } from '@/types/property';
import { safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { exportCsv } from '@/lib/csv';

export function PropertiesPage() {
  const { data, loading, error, refresh } = useFirestoreQuery(() => listProperties(180), []);
  const [search, setSearch] = useState('');
  const [city, setCity] = useState('');
  const [usage, setUsage] = useState('all');

  const filtered = useMemo(() => (data ?? []).filter((property) => {
    const q = search.trim().toLowerCase();
    const matchSearch = !q || [property.id, property.title, property.ownerName, property.city, property.district, property.type].join(' ').toLowerCase().includes(q);
    const matchCity = !city || String(property.city ?? '').toLowerCase().includes(city.toLowerCase());
    const matchUsage = usage === 'all' || property.usage === usage;
    return matchSearch && matchCity && matchUsage;
  }), [data, search, city, usage]);

  const usages = Array.from(new Set((data ?? []).map((p) => p.usage).filter(Boolean))) as string[];
  const columns = useMemo<ColumnDef<Property>[]>(() => [
    { accessorKey: 'title', header: 'العقار', cell: ({ row }) => <Link to={`/properties/${row.original.id}`}><strong>{safeText(row.original.title || row.original.ownerName || row.original.id)}</strong><div className="page-subtitle" style={{ margin: 0 }}>{safeText(row.original.district, '')}</div></Link> },
    { accessorKey: 'city', header: 'المدينة', cell: ({ row }) => safeText(row.original.city) },
    { accessorKey: 'type', header: 'النوع', cell: ({ row }) => safeText(row.original.type) },
    { accessorKey: 'usage', header: 'الاستخدام', cell: ({ row }) => safeText(row.original.usage) },
    { accessorKey: 'units', header: 'الوحدات', cell: ({ row }) => <Badge tone="gold">{row.original.units?.length ?? 0} وحدة</Badge> },
    { accessorKey: 'createdAt', header: 'التاريخ', cell: ({ row }) => formatDate(row.original.createdAt) },
    { id: 'actions', header: 'فتح', cell: ({ row }) => <Link to={`/properties/${row.original.id}`}><Button variant="soft">تفاصيل</Button></Link> },
  ], []);

  function exportRows() {
    exportCsv('properties.csv', filtered.map((p) => ({ id: p.id, title: p.title, ownerName: p.ownerName, city: p.city, district: p.district, type: p.type, usage: p.usage, units: p.units?.length ?? 0 })));
  }

  return <div className="stack">
    <PageHeader title="العقارات والوحدات" subtitle="إدارة العقارات وربطها بالعقود والوحدات." actions={<><Button variant="soft" onClick={refresh}>تحديث</Button><Button variant="gold" onClick={exportRows}>تصدير CSV</Button></>} />
    <div className="card" style={{ padding: 14 }}><div className="filters-bar" style={{ gridTemplateColumns: '2fr 1fr 1fr' }}><Field label="بحث"><Input value={search} onChange={(e) => setSearch(e.target.value)} /></Field><Field label="المدينة"><Input value={city} onChange={(e) => setCity(e.target.value)} /></Field><Field label="الاستخدام"><Select value={usage} onChange={(e) => setUsage(e.target.value)}><option value="all">الكل</option>{usages.map((u) => <option key={u} value={u}>{u}</option>)}</Select></Field></div></div>
    {loading && <TableSkeleton />}
    {error && <ErrorState message={error} onRetry={refresh} />}
    {!loading && !error && <DataGrid data={filtered} columns={columns} mobileTitle={(row) => safeText(row.title || row.ownerName || row.id)} mobileSubtitle={(row) => `${safeText(row.city)} · ${safeText(row.district)}`} mobileMeta={(row) => <><Badge tone="gold">{row.units?.length ?? 0} وحدة</Badge> <Badge tone="gray">{safeText(row.type)}</Badge></>} mobileActions={(row) => <Link to={`/properties/${row.id}`}><Button variant="soft">فتح</Button></Link>} />}
  </div>;
}
