import { Link } from 'react-router-dom';
import { logout } from '@/services/authService';
import { Button } from '@/components/ui/Button';

export function AccessDeniedPage() {
  return <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: 20 }}>
    <div className="card" style={{ padding: 30, maxWidth: 560, textAlign: 'center' }}>
      <div className="brand-mark" style={{ margin: '0 auto 16px' }}>!</div>
      <h1 className="page-title">تم رفض الوصول</h1>
      <p className="page-subtitle">حسابك مسجل في Firebase Auth، لكنه غير موجود كأدمن نشط داخل `adminUsers/{'{uid}'}` أو أن `active` ليست true.</p>
      <div style={{ display: 'flex', gap: 10, justifyContent: 'center', marginTop: 18, flexWrap: 'wrap' }}>
        <Link to="/login"><Button variant="gold">العودة للدخول</Button></Link>
        <Button variant="soft" onClick={() => logout()}>تسجيل خروج</Button>
      </div>
    </div>
  </div>;
}
