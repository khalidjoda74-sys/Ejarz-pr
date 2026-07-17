import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';
import { Field, Input, Select } from '@/components/ui/Field';
import { InfoItem } from '@/components/ui/InfoItem';
import { ConfirmDialog } from '@/components/feedback/ConfirmDialog';
import { ErrorState } from '@/components/feedback/ErrorState';
import { FullPageLoader } from '@/components/feedback/FullPageLoader';
import { useToast } from '@/components/feedback/Toast';
import { useAuth } from '@/hooks/useAuth';
import { usePermissions } from '@/hooks/usePermissions';
import { getAdminUser, setAdminActive, upsertAdmin } from '@/services/adminService';
import { AdminUser, ADMIN_ROLES, ALL_PERMISSIONS } from '@/types/admin';
import { roleLabel, safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { getErrorMessage } from '@/lib/errors';

export function AdminDetailsPage() {
  const { uid = '' } = useParams();
  const { admin: currentAdmin } = useAuth();
  const { isOwner } = usePermissions();
  const toast = useToast();
  const [record, setRecord] = useState<AdminUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState(false);
  async function load() { setLoading(true); setError(null); try { setRecord(await getAdminUser(uid)); } catch (err) { setError(getErrorMessage(err)); } finally { setLoading(false); } }
  useEffect(() => { load(); }, [uid]);
  async function savePatch(patch: Partial<AdminUser>) { if (!isOwner || !record) return; try { await upsertAdmin(record.uid, patch); toast.push('تم حفظ التعديل', 'success'); await load(); } catch (err) { toast.push(getErrorMessage(err), 'error'); } }
  async function toggleActive() { if (!isOwner || !record) return; if (record.uid === currentAdmin?.uid && record.role === 'owner' && record.active) { toast.push('لا يمكن تعطيل نفسك كمالك نشط من هذه الصفحة', 'error'); return; } try { await setAdminActive(record.uid, !record.active); toast.push('تم تحديث حالة الأدمن', 'success'); setConfirm(false); await load(); } catch (err) { toast.push(getErrorMessage(err), 'error'); } }
  if (loading) return <FullPageLoader label="جاري تحميل الأدمن" />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!record) return <ErrorState message="الأدمن غير موجود" onRetry={load} />;
  const permissions = record.permissions ?? [];
  return <div className="stack"><PageHeader title="تفاصيل الأدمن" subtitle="تعديل الدور والصلاحيات والتفعيل." actions={<><Link to="/admins"><Button variant="soft">رجوع</Button></Link>{isOwner && <Button variant={record.active ? 'danger' : 'gold'} onClick={() => setConfirm(true)}>{record.active ? 'تعطيل' : 'تفعيل'}</Button>}</>} />
    <section className="detail-hero"><div><Badge tone={record.active ? 'green' : 'red'}>{record.active ? 'نشط' : 'معطل'}</Badge><h1 className="page-title" style={{ marginTop: 12 }}>{safeText(record.displayName || record.email || record.uid)}</h1><p>{roleLabel(record.role)} · {safeText(record.email)}</p></div></section>
    <div className="grid-2"><Card style={{ padding: 18 }}><h2 className="section-title">البيانات</h2><div className="info-grid"><InfoItem label="UID" value={record.uid} /><InfoItem label="البريد" value={record.email} /><InfoItem label="آخر دخول" value={formatDate(record.lastLoginAt)} /><InfoItem label="تاريخ الإنشاء" value={formatDate(record.createdAt)} /></div></Card><Card style={{ padding: 18 }}><h2 className="section-title">الدور</h2><Field label="الدور"><Select disabled={!isOwner} value={record.role} onChange={(e) => savePatch({ role: e.target.value as AdminUser['role'] })}>{ADMIN_ROLES.map((role) => <option key={role} value={role}>{roleLabel(role)}</option>)}</Select></Field></Card></div>
    <Card style={{ padding: 18 }}><h2 className="section-title">الصلاحيات التفصيلية</h2><div className="grid-3">{ALL_PERMISSIONS.map((permission) => <label key={permission} className="card-solid" style={{ padding: 12, display: 'flex', gap: 10, alignItems: 'center' }}><input disabled={!isOwner} type="checkbox" checked={permissions.includes(permission)} onChange={(e) => { const next = e.target.checked ? [...permissions, permission] : permissions.filter((p) => p !== permission); savePatch({ permissions: next }); }} /><span>{permission}</span></label>)}</div></Card>
    <ConfirmDialog open={confirm} danger={record.active} title={record.active ? 'تعطيل الأدمن؟' : 'تفعيل الأدمن؟'} description="لا يوجد حذف نهائي؛ سيتم تغيير active فقط." onCancel={() => setConfirm(false)} onConfirm={toggleActive} />
  </div>;
}
