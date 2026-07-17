import { PageHeader } from '@/components/layout/PageHeader';
import { Card } from '@/components/ui/Card';
import { Badge } from '@/components/ui/Badge';
import { isFirebaseConfigured, missingFirebaseKeys } from '@/lib/env';
import { useAuth } from '@/hooks/useAuth';
import { roleLabel, safeText } from '@/lib/formatters';

export function SettingsPage() {
  const { admin, user } = useAuth();
  const configured = isFirebaseConfigured();
  return <div className="stack"><PageHeader title="الإعدادات" subtitle="معلومات البيئة والحساب وقابلية النشر." />
    <div className="grid-2"><Card style={{ padding: 18 }}><h2 className="section-title">Firebase</h2><Badge tone={configured ? 'green' : 'red'}>{configured ? 'جاهز' : 'ناقص env'}</Badge><p className="page-subtitle">Project ID: ejarz-pro-20260624</p>{!configured && <p className="page-subtitle">المفاتيح الناقصة: {missingFirebaseKeys().join(', ')}</p>}</Card><Card style={{ padding: 18 }}><h2 className="section-title">الحساب الحالي</h2><div className="info-grid"><div className="info-item"><span>Firebase UID</span><strong>{safeText(user?.uid)}</strong></div><div className="info-item"><span>الأدمن</span><strong>{safeText(admin?.displayName || admin?.email)}</strong></div><div className="info-item"><span>الدور</span><strong>{roleLabel(admin?.role)}</strong></div><div className="info-item"><span>الحالة</span><strong>{admin?.active ? 'نشط' : 'غير نشط'}</strong></div></div></Card></div>
    <Card style={{ padding: 18 }} goldLine><h2 className="section-title">ملاحظات النشر</h2><p className="page-subtitle">بعد ملء `.env.local` شغّل `npm run build` ثم انشر dist على Firebase Hosting. ملف firebase.json يحتوي rewrite لدعم React Router.</p></Card>
  </div>;
}
