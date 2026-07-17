import { ColumnDef } from '@tanstack/react-table';
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select } from '@/components/ui/Field';
import { UserStatusBadge } from '@/components/ui/Badge';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listUsers } from '@/services/userService';
import { AppUser } from '@/types/user';
import { safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { exportCsv } from '@/lib/csv';

export function UsersPage() {
  const { data, loading, error, refresh } = useFirestoreQuery(() => listUsers(180), []);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('all');

  const filtered = useMemo(() => (data ?? []).filter((user) => {
    const q = search.trim().toLowerCase();
    const matchSearch = !q || [user.uid, user.id, user.displayName, user.name, user.phone, user.email].join(' ').toLowerCase().includes(q);
    const userStatus = user.blocked ? 'blocked' : user.status ?? 'active';
    const matchStatus = status === 'all' || status === userStatus;
    return matchSearch && matchStatus;
  }), [data, search, status]);

  const columns = useMemo<ColumnDef<AppUser>[]>(() => [
    { accessorKey: 'displayName', header: 'المستخدم', cell: ({ row }) => <Link to={`/users/${row.original.uid || row.original.id}`}><strong>{safeText(row.original.displayName || row.original.name || row.original.phone)}</strong><div className="page-subtitle" style={{ margin: 0 }}>{safeText(row.original.email, '')}</div></Link> },
    { accessorKey: 'phone', header: 'الجوال', cell: ({ row }) => safeText(row.original.phone) },
    { accessorKey: 'status', header: 'الحالة', cell: ({ row }) => <UserStatusBadge blocked={row.original.blocked} status={row.original.status} /> },
    { accessorKey: 'lastLoginAt', header: 'آخر دخول', cell: ({ row }) => formatDate(row.original.lastLoginAt) },
    { accessorKey: 'createdAt', header: 'تاريخ التسجيل', cell: ({ row }) => formatDate(row.original.createdAt) },
    { id: 'actions', header: 'فتح', cell: ({ row }) => <Link to={`/users/${row.original.uid || row.original.id}`}><Button variant="soft">تفاصيل</Button></Link> },
  ], []);

  function exportRows() {
    exportCsv('users.csv', filtered.map((user) => ({ uid: user.uid || user.id, name: user.displayName || user.name, phone: user.phone, email: user.email, status: user.blocked ? 'blocked' : user.status, createdAt: formatDate(user.createdAt) })));
  }

  return <div className="stack">
    <PageHeader title="المستخدمون" subtitle="إدارة العملاء وحالات الحسابات وبيانات FCM." actions={<><Button variant="soft" onClick={refresh}>تحديث</Button><Button variant="gold" onClick={exportRows}>تصدير CSV</Button></>} />
    <div className="card" style={{ padding: 14 }}>
      <div className="filters-bar" style={{ gridTemplateColumns: '2fr 1fr' }}>
        <Field label="بحث"><Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="اسم، جوال، بريد، UID" /></Field>
        <Field label="الحالة"><Select value={status} onChange={(e) => setStatus(e.target.value)}><option value="all">كل الحالات</option><option value="active">نشط</option><option value="blocked">محظور</option><option value="suspended">موقوف</option></Select></Field>
      </div>
    </div>
    {loading && <TableSkeleton />}
    {error && <ErrorState message={error} onRetry={refresh} />}
    {!loading && !error && <DataGrid
      data={filtered}
      columns={columns}
      mobileTitle={(row) => safeText(row.displayName || row.name || row.phone)}
      mobileSubtitle={(row) => safeText(row.email || row.uid || row.id)}
      mobileMeta={(row) => <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}><UserStatusBadge blocked={row.blocked} status={row.status} /><span className="badge badge-gray">{formatDate(row.createdAt)}</span></div>}
      mobileActions={(row) => <Link to={`/users/${row.uid || row.id}`}><Button variant="soft">فتح</Button></Link>}
    />}
  </div>;
}
