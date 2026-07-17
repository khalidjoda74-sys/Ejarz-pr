import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Badge, StatusBadge, UserStatusBadge } from '@/components/ui/Badge';
import { Field, Textarea } from '@/components/ui/Field';
import { InfoItem } from '@/components/ui/InfoItem';
import { ConfirmDialog } from '@/components/feedback/ConfirmDialog';
import { ErrorState } from '@/components/feedback/ErrorState';
import { FullPageLoader } from '@/components/feedback/FullPageLoader';
import { useToast } from '@/components/feedback/Toast';
import { useAuth } from '@/hooks/useAuth';
import { getUser, listUserContracts, listUserFcmTokens, listUserProperties, setUserBlocked } from '@/services/userService';
import { AppUser, FcmToken } from '@/types/user';
import { Contract } from '@/types/contract';
import { Property } from '@/types/property';
import { formatDate } from '@/lib/dates';
import { safeText } from '@/lib/formatters';
import { getErrorMessage } from '@/lib/errors';

export function UserDetailsPage() {
  const { uid = '' } = useParams();
  const { admin } = useAuth();
  const toast = useToast();
  const [user, setUser] = useState<AppUser | null>(null);
  const [contracts, setContracts] = useState<Contract[]>([]);
  const [properties, setProperties] = useState<Property[]>([]);
  const [tokens, setTokens] = useState<FcmToken[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [confirm, setConfirm] = useState(false);

  async function load() {
    setLoading(true); setError(null);
    try {
      const record = await getUser(uid);
      setUser(record);
      setContracts(await listUserContracts(uid).catch(() => []));
      setProperties(await listUserProperties(uid).catch(() => []));
      setTokens(await listUserFcmTokens(uid).catch(() => []));
    } catch (err) { setError(getErrorMessage(err)); } finally { setLoading(false); }
  }

  useEffect(() => { load(); }, [uid]);

  async function toggleBlock() {
    if (!admin || !user) return;
    try {
      await setUserBlocked(admin, user, !(user.blocked || user.status === 'blocked'), reason);
      toast.push('تم تحديث حالة المستخدم', 'success');
      setConfirm(false); setReason(''); await load();
    } catch (err) { toast.push(getErrorMessage(err), 'error'); }
  }

  if (loading) return <FullPageLoader label="جاري تحميل ملف المستخدم" />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!user) return <ErrorState message="المستخدم غير موجود" onRetry={load} />;

  const blocked = Boolean(user.blocked || user.status === 'blocked');

  return <div className="stack">
    <PageHeader title="ملف المستخدم" subtitle="عرض بيانات العميل، العقود، العقارات، والتوكنات." actions={<><Link to="/users"><Button variant="soft">رجوع</Button></Link><Button variant={blocked ? 'gold' : 'danger'} onClick={() => setConfirm(true)}>{blocked ? 'فك الحظر' : 'حظر المستخدم'}</Button></>} />
    <section className="detail-hero">
      <div>
        <UserStatusBadge blocked={blocked} status={user.status} />
        <h1 className="page-title" style={{ marginTop: 12 }}>{safeText(user.displayName || user.name || user.phone)}</h1>
        <p>{safeText(user.email)} · {safeText(user.phone)} · {safeText(user.uid || user.id)}</p>
      </div>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}><Badge tone="gold">{contracts.length} عقود</Badge><Badge tone="navy">{properties.length} عقارات</Badge><Badge tone="green">{tokens.filter(t => t.active).length} FCM نشط</Badge></div>
    </section>
    <div className="grid-2">
      <div className="stack">
        <Card style={{ padding: 18 }}><h2 className="section-title">البيانات الأساسية</h2><div className="info-grid"><InfoItem label="الاسم" value={user.displayName || user.name} /><InfoItem label="الجوال" value={user.phone} /><InfoItem label="البريد" value={user.email} /><InfoItem label="UID" value={user.uid || user.id} /><InfoItem label="تاريخ التسجيل" value={formatDate(user.createdAt)} /><InfoItem label="آخر دخول" value={formatDate(user.lastLoginAt)} /></div></Card>
        <Card style={{ padding: 18 }}><h2 className="section-title">عقود المستخدم</h2><div className="stack">{contracts.map(contract => <Link className="card-solid" style={{ padding: 12 }} key={contract.id} to={`/contracts/${contract.id}`}><strong>{contract.orderNumber || contract.id}</strong><div style={{ marginTop: 8 }}><StatusBadge status={contract.status} /></div></Link>)}{!contracts.length && <p className="page-subtitle">لا توجد عقود.</p>}</div></Card>
      </div>
      <div className="stack">
        <Card style={{ padding: 18 }}><h2 className="section-title">العقارات</h2><div className="stack">{properties.map(property => <Link className="card-solid" style={{ padding: 12 }} key={property.id} to={`/properties/${property.id}`}><strong>{safeText(property.title || property.ownerName || property.id)}</strong><p className="page-subtitle" style={{ margin: 0 }}>{safeText(property.city)} · {safeText(property.district)}</p></Link>)}{!properties.length && <p className="page-subtitle">لا توجد عقارات.</p>}</div></Card>
        <Card style={{ padding: 18 }}><h2 className="section-title">FCM Tokens</h2><div className="stack">{tokens.map(token => <div className="card-solid" style={{ padding: 12 }} key={token.id}><Badge tone={token.active ? 'green' : 'gray'}>{token.active ? 'نشط' : 'غير نشط'}</Badge><p className="page-subtitle" style={{ wordBreak: 'break-all' }}>{safeText(token.token)}</p><p className="page-subtitle">{safeText(token.platform)} · {formatDate(token.lastSeenAt || token.updatedAt)}</p></div>)}{!tokens.length && <p className="page-subtitle">لا توجد توكنات.</p>}</div></Card>
      </div>
    </div>
    <ConfirmDialog open={confirm} danger={!blocked} title={blocked ? 'فك حظر المستخدم؟' : 'حظر المستخدم؟'} description={blocked ? 'سيتم إعادة حالة المستخدم إلى نشط.' : 'يفضل كتابة سبب واضح للحظر.'} confirmLabel={blocked ? 'فك الحظر' : 'حظر'} onCancel={() => setConfirm(false)} onConfirm={toggleBlock} />
    {confirm && !blocked && <div className="modal-panel" style={{ top: 'calc(50% + 110px)', zIndex: 140 }}><Field label="سبب الحظر"><Textarea value={reason} onChange={(e) => setReason(e.target.value)} /></Field></div>}
  </div>;
}
