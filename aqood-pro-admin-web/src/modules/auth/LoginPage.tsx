import { useState } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { z } from 'zod';
import { loginWithEmail } from '@/services/authService';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/Button';
import { Field, Input } from '@/components/ui/Field';
import { getErrorMessage } from '@/lib/errors';
import { isFirebaseConfigured, missingFirebaseKeys } from '@/lib/env';

const loginSchema = z.object({
  email: z.string().email('اكتب بريدًا صحيحًا'),
  password: z.string().min(6, 'كلمة المرور قصيرة'),
});

export function LoginPage() {
  const { user, admin } = useAuth();
  const location = useLocation();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const configured = isFirebaseConfigured();

  if (user && admin?.active) return <Navigate to={(location.state as { from?: string } | null)?.from ?? '/dashboard'} replace />;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    const parsed = loginSchema.safeParse({ email, password });
    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? 'تحقق من البيانات');
      return;
    }
    setLoading(true);
    try {
      await loginWithEmail(email, password);
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }

  return <div className="login-page">
    <section className="login-panel">
      <div className="brand-mark" style={{ marginBottom: 18 }}>عق</div>
      <h1 className="page-title">دخول مركز تحكم عقود برو</h1>
      <p className="page-subtitle">بوابة إدارية آمنة مرتبطة بـ Firebase Auth و adminUsers.</p>
      {!configured && <div className="card-solid" style={{ padding: 12, margin: '16px 0', borderColor: 'rgba(220,38,38,.25)' }}>
        <span className="badge badge-red">إعداد مطلوب</span>
        <p className="page-subtitle">أكمل مفاتيح Firebase في `.env.local`: {missingFirebaseKeys().join(', ')}</p>
      </div>}
      <form onSubmit={submit} className="stack" style={{ marginTop: 20 }}>
        <Field label="البريد الإلكتروني"><Input value={email} onChange={(e) => setEmail(e.target.value)} type="email" placeholder="admin@example.com" /></Field>
        <Field label="كلمة المرور"><Input value={password} onChange={(e) => setPassword(e.target.value)} type="password" placeholder="••••••••" /></Field>
        {error && <div className="badge badge-red" style={{ justifyContent: 'flex-start' }}>{error}</div>}
        <Button type="submit" variant="gold" disabled={loading}>{loading ? 'جاري الدخول...' : 'دخول آمن'}</Button>
      </form>
    </section>
    <section className="login-art">
      <div className="command-orb">
        <div style={{ textAlign: 'center', maxWidth: 260 }}>
          <div style={{ fontSize: '3rem', fontWeight: 900, color: 'var(--gold-400)' }}>398</div>
          <div style={{ color: 'rgba(255,255,255,.76)' }}>رسوم العقد الجاهزة للمتابعة: 299 إيجار + 99 عقود برو</div>
        </div>
      </div>
      <h2 style={{ fontSize: 'clamp(2rem, 5vw, 4rem)', margin: '28px 0 8px', letterSpacing: '-.05em' }}>Aqood Pro Command Center</h2>
      <p style={{ color: 'rgba(255,255,255,.72)', lineHeight: 1.9 }}>تصميم إداري فخم، سريع، ومتوافق مع الجوال لمتابعة العقود، النواقص، المدفوعات، والعملاء من شاشة واحدة.</p>
    </section>
  </div>;
}
