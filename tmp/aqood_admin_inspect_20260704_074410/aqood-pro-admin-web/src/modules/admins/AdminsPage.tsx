import { ColumnDef } from '@tanstack/react-table';
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';
import { Field, Input, Select } from '@/components/ui/Field';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { usePermissions } from '@/hooks/usePermissions';
import { listAdmins, upsertAdmin } from '@/services/adminService';
import { AdminUser, ADMIN_ROLES } from '@/types/admin';
import { roleLabel, safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { useToast } from '@/components/feedback/Toast';
import { getErrorMessage } from '@/lib/errors';

export function AdminsPage() {
  const { isOwner } = usePermissions();
  const toast = useToast();
  const { data, loading, error, refresh } = useFirestoreQuery(() => listAdmins(), []);
  const [uid, setUid] = useState('');
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<AdminUser['role']>('reviewer');

  const columns = useMemo<ColumnDef<AdminUser & { id: string }>[]>(() => [
    { accessorKey: 'displayName', header: 'الأدمن', cell: ({ row }) => <Link to={`/admins/${row.original.uid || row.original.id}`}><strong>{safeText(row.original.displayName || row.original.email || row.original.uid)}</strong><div className="page-subtitle" style={{ margin: 0 }}>{safeText(row.original.email)}</div></Link> },
    { accessorKey: 'role', header: 'الدور', cell: ({ row }) => <Badge tone="gold">{roleLabel(row.original.role)}</Badge> },
    { accessorKey: 'active', header: 'الحالة', cell: ({ row }) => <Badge tone={row.original.active ? 'green' : 'red'}>{row.original.active ? 'نشط' : 'معطل'}</Badge> },
    { accessorKey: 'lastLoginAt', header: 'آخر دخول', cell: ({ row }) => formatDate(row.original.lastLoginAt) },
    { id: 'actions', header: 'فتح', cell: ({ row }) => <Link to={`/admins/${row.original.uid || row.original.id}`}><Button variant="soft">إدارة</Button></Link> },
  ], []);

  async function addAdmin(event: React.FormEvent) {
    event.preventDefault();
    if (!isOwner || !uid.trim()) return;
    try {
      await upsertAdmin(uid.trim(), { uid: uid.trim(), email, role, active: true, permissions: [] });
      toast.push('تم إضافة الأدمن أو تحديثه', 'success');
      setUid(''); setEmail(''); setRole('reviewer'); refresh();
    } catch (err) { toast.push(getErrorMessage(err), 'error'); }
  }

  return <div className="stack"><PageHeader title="الأدمن والصلاحيات" subtitle="إدارة adminUsers والأدوار. owner فقط يستطيع التعديل." actions={<Button variant="soft" onClick={refresh}>تحديث</Button>} />
    {isOwner && <div className="card" style={{ padding: 18 }}><form onSubmit={addAdmin} className="filters-bar" style={{ gridTemplateColumns: '1.2fr 1.2fr 1fr auto' }}><Field label="UID"><Input value={uid} onChange={(e) => setUid(e.target.value)} required /></Field><Field label="البريد"><Input value={email} onChange={(e) => setEmail(e.target.value)} /></Field><Field label="الدور"><Select value={role} onChange={(e) => setRole(e.target.value as AdminUser['role'])}>{ADMIN_ROLES.map((r) => <option key={r} value={r}>{roleLabel(r)}</option>)}</Select></Field><Button variant="gold" style={{ alignSelf: 'end' }}>إضافة أدمن</Button></form></div>}
    {!isOwner && <div className="card" style={{ padding: 16 }}><Badge tone="orange">صلاحية محدودة</Badge><p className="page-subtitle">تحتاج owner لإدارة الأدمن.</p></div>}
    {loading && <TableSkeleton />}{error && <ErrorState message={error} onRetry={refresh} />}{!loading && !error && <DataGrid data={data ?? []} columns={columns} mobileTitle={(row) => safeText(row.displayName || row.email || row.uid)} mobileSubtitle={(row) => roleLabel(row.role)} mobileMeta={(row) => <Badge tone={row.active ? 'green' : 'red'}>{row.active ? 'نشط' : 'معطل'}</Badge>} mobileActions={(row) => <Link to={`/admins/${row.uid || row.id}`}><Button variant="soft">فتح</Button></Link>} />}
  </div>;
}
