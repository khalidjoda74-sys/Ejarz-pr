import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select, Textarea } from '@/components/ui/Field';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/components/feedback/Toast';
import { createNotification } from '@/services/notificationService';
import { getErrorMessage } from '@/lib/errors';

export function NotificationNewPage() {
  const { admin } = useAuth();
  const toast = useToast();
  const navigate = useNavigate();
  const [uid, setUid] = useState('');
  const [contractId, setContractId] = useState('');
  const [type, setType] = useState('general');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [priority, setPriority] = useState<'normal' | 'high'>('normal');
  const [loading, setLoading] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!admin) return;
    setLoading(true);
    try {
      await createNotification(admin, {
        uid: uid || undefined,
        contractId: contractId || undefined,
        type,
        title,
        body,
        priority,
      });
      toast.push('تم إنشاء الإشعار', 'success');
      navigate('/notifications');
    } catch (err) { toast.push(getErrorMessage(err), 'error'); } finally { setLoading(false); }
  }

  return <div className="stack"><PageHeader title="إشعار جديد" subtitle="إنشاء إشعار داخلي مرتبط بعقد أو مستخدم." />
    <Card style={{ padding: 18, maxWidth: 760 }}><form onSubmit={submit} className="stack"><Field label="UID المستخدم"><Input value={uid} onChange={(e) => setUid(e.target.value)} placeholder="مطلوب إذا لم تدخل Contract ID" /></Field><Field label="Contract ID"><Input value={contractId} onChange={(e) => setContractId(e.target.value)} placeholder="اختياري، وسيتم استنتاج UID من العقد" /></Field><Field label="نوع الإشعار"><Select value={type} onChange={(e) => setType(e.target.value)}><option value="general">عام</option><option value="contractMessage">رسالة عقد</option><option value="awaitingPayment">بانتظار الدفع</option><option value="processing">قيد المعالجة</option><option value="missingRequirement">نقص مطلوب</option><option value="finalPdfUploaded">تم إصدار العقد</option><option value="authenticated">مكتمل</option><option value="rejected">مرفوض</option></Select></Field><Field label="العنوان"><Input value={title} onChange={(e) => setTitle(e.target.value)} required /></Field><Field label="النص"><Textarea value={body} onChange={(e) => setBody(e.target.value)} required /></Field><Field label="الأولوية"><Select value={priority} onChange={(e) => setPriority(e.target.value as 'normal' | 'high')}><option value="normal">عادية</option><option value="high">عالية</option></Select></Field><Button variant="gold" disabled={loading}>{loading ? 'جاري الحفظ...' : 'إنشاء الإشعار'}</Button></form></Card>
  </div>;
}
