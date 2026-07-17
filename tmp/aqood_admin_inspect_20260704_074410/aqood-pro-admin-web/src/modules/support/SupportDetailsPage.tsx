import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Field, Select, Textarea } from '@/components/ui/Field';
import { InfoItem } from '@/components/ui/InfoItem';
import { ErrorState } from '@/components/feedback/ErrorState';
import { FullPageLoader } from '@/components/feedback/FullPageLoader';
import { useToast } from '@/components/feedback/Toast';
import { useAuth } from '@/hooks/useAuth';
import { addSupportReply, getSupportTicket, updateTicketStatus } from '@/services/supportService';
import { SupportTicket, SupportTicketStatus } from '@/types/support';
import { SupportBadge } from './SupportPage';
import { formatDate } from '@/lib/dates';
import { getErrorMessage } from '@/lib/errors';

export function SupportDetailsPage() {
  const { ticketId = '' } = useParams();
  const { admin } = useAuth();
  const toast = useToast();
  const [ticket, setTicket] = useState<SupportTicket | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reply, setReply] = useState('');
  const [visibility, setVisibility] = useState<'admin' | 'customer'>('customer');
  const [status, setStatus] = useState<SupportTicketStatus>('open');
  async function load() { setLoading(true); setError(null); try { const t = await getSupportTicket(ticketId); setTicket(t); if (t) setStatus(t.status); } catch (err) { setError(getErrorMessage(err)); } finally { setLoading(false); } }
  useEffect(() => { load(); }, [ticketId]);
  async function submitReply() { if (!admin || !reply.trim()) return; try { await addSupportReply(admin, ticketId, reply, visibility); toast.push('تم إضافة الرد', 'success'); setReply(''); await load(); } catch (err) { toast.push(getErrorMessage(err), 'error'); } }
  async function submitStatus() { if (!admin || !ticket) return; try { await updateTicketStatus(admin, ticket, status); toast.push('تم تحديث الحالة', 'success'); await load(); } catch (err) { toast.push(getErrorMessage(err), 'error'); } }
  if (loading) return <FullPageLoader label="جاري تحميل التذكرة" />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!ticket) return <ErrorState message="التذكرة غير موجودة" onRetry={load} />;
  return <div className="stack"><PageHeader title="تفاصيل التذكرة" subtitle="رد إداري وتحديث الحالة وربط التذكرة." actions={<Link to="/support"><Button variant="soft">رجوع</Button></Link>} />
    <section className="detail-hero"><div><SupportBadge status={ticket.status} /><h1 className="page-title" style={{ marginTop: 12 }}>{ticket.subject}</h1><p>{ticket.message}</p></div></section>
    <div className="grid-2"><Card style={{ padding: 18 }}><h2 className="section-title">بيانات التذكرة</h2><div className="info-grid"><InfoItem label="المستخدم" value={ticket.userId} /><InfoItem label="العقد" value={ticket.contractId} /><InfoItem label="الأولوية" value={ticket.priority} /><InfoItem label="التاريخ" value={formatDate(ticket.createdAt)} /></div></Card><Card style={{ padding: 18 }}><h2 className="section-title">تغيير الحالة</h2><Field label="الحالة"><Select value={status} onChange={(e) => setStatus(e.target.value as SupportTicketStatus)}><option value="open">مفتوحة</option><option value="pending">بانتظار العميل</option><option value="resolved">محلولة</option><option value="closed">مغلقة</option></Select></Field><Button variant="gold" style={{ marginTop: 10 }} onClick={submitStatus}>حفظ الحالة</Button></Card></div>
    <Card style={{ padding: 18 }}><h2 className="section-title">الردود</h2><div className="timeline">{ticket.replies?.map((r) => <div className="timeline-item" key={r.id}><strong>{r.createdByName}</strong><p>{r.message}</p><p className="page-subtitle">{r.visibility === 'admin' ? 'داخلي' : 'للعميل'} · {formatDate(r.createdAt)}</p></div>)}{!ticket.replies?.length && <p className="page-subtitle">لا توجد ردود.</p>}</div><div className="stack" style={{ marginTop: 16 }}><Field label="رد جديد"><Textarea value={reply} onChange={(e) => setReply(e.target.value)} /></Field><Field label="الظهور"><Select value={visibility} onChange={(e) => setVisibility(e.target.value as 'admin' | 'customer')}><option value="customer">للعميل</option><option value="admin">داخلي للإدارة</option></Select></Field><Button variant="gold" onClick={submitReply}>إرسال الرد</Button></div></Card>
  </div>;
}
