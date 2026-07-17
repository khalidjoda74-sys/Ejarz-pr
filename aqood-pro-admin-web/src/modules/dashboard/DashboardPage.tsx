import { Link } from 'react-router-dom';
import { useMemo } from 'react';
import { PageHeader } from '@/components/layout/PageHeader';
import { Card, SolidCard } from '@/components/ui/Card';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { ErrorState } from '@/components/feedback/ErrorState';
import { KpiSkeleton } from '@/components/feedback/Skeletons';
import { StatusPie, SimpleBarChart } from '@/components/charts/Charts';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listContracts } from '@/services/contractService';
import { listUsers } from '@/services/userService';
import { listNotifications } from '@/services/notificationService';
import { listSupportTickets } from '@/services/supportService';
import { listAuditLogs } from '@/services/auditService';
import { summarizeContracts, summarizeUsers } from '@/services/reportService';
import { formatCurrency, safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';

export function DashboardPage() {
  const query = useFirestoreQuery(async () => {
    const [contracts, users, notifications, supportTickets, auditLogs] = await Promise.all([
      listContracts(160),
      listUsers(120),
      listNotifications(20),
      listSupportTickets(30),
      listAuditLogs(12),
    ]);
    return { contracts, users, notifications, supportTickets, auditLogs: auditLogs.slice(0, 12) };
  }, []);

  const summary = useMemo(() => query.data ? summarizeContracts(query.data.contracts) : null, [query.data]);
  const userSummary = useMemo(() => query.data ? summarizeUsers(query.data.users) : null, [query.data]);

  if (query.loading) return <><PageHeader title="مركز العمليات" subtitle="جاري تحميل المؤشرات من Firebase الحقيقي." /><KpiSkeleton /></>;
  if (query.error) return <ErrorState message={query.error} onRetry={query.refresh} />;
  if (!query.data || !summary || !userSummary) return null;

  const urgent = query.data.contracts.filter((contract) => ['missingData', 'awaitingPayment', 'processing'].includes(contract.status)).slice(0, 6);
  const openTickets = query.data.supportTickets.filter((ticket) => ticket.status === 'open');

  return <div className="stack">
    <PageHeader
      title="مركز العمليات"
      subtitle="لوحة قيادة عقود برو: متابعة العقود، النواقص، المدفوعات، والدعم من شاشة واحدة."
      actions={<Button variant="soft" onClick={query.refresh}>تحديث البيانات</Button>}
    />
    <div className="kpi-grid">
      <Kpi title="إجمالي المستخدمين" value={userSummary.total} hint={`اليوم: ${userSummary.today}`} />
      <Kpi title="إجمالي العقود" value={summary.total} hint={`اليوم: ${summary.today}`} />
      <Kpi title="بانتظار الدفع" value={summary.awaitingPayment} hint="تحتاج متابعة مالية" tone="orange" />
      <Kpi title="النواقص" value={summary.missingData} hint="بانتظار العميل" tone="red" />
      <Kpi title="مكتملة" value={summary.completed} hint="authenticated" tone="green" />
      <Kpi title="إجمالي الرسوم" value={formatCurrency(summary.totalFees)} hint="حسب العقود المكتملة/المعتمدة" />
      <Kpi title="رسوم منصة إيجار" value={formatCurrency(summary.ejarPlatformFees)} hint="299 ريال لكل عقد" tone="gold" />
      <Kpi title="عمولة عقود برو" value={formatCurrency(summary.serviceFees)} hint="99 ريال لكل عقد" tone="gold" />
    </div>

    <div className="grid-2">
      <Card style={{ padding: 18 }} goldLine>
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'center' }}>
          <div>
            <h2 className="section-title">خريطة حالات العقود</h2>
            <p className="page-subtitle">توزيع العقود حسب دورة الحالة الحالية.</p>
          </div>
          <Badge tone="gold">Pipeline</Badge>
        </div>
        <StatusPie data={summary.byStatus} />
        <div className="grid-3">
          {summary.byStatus.filter((item) => item.count > 0).slice(0, 6).map((item) => <SolidCard key={item.status} style={{ padding: 12 }}>
            <StatusBadge status={item.status} />
            <div className="kpi-value" style={{ fontSize: '1.3rem', marginTop: 8 }}>{item.count}</div>
          </SolidCard>)}
        </div>
      </Card>

      <Card style={{ padding: 18 }}>
        <h2 className="section-title">طلبات تحتاج تدخل الآن</h2>
        <div className="stack">
          {urgent.length === 0 && <p className="page-subtitle">لا توجد طلبات عاجلة حاليًا.</p>}
          {urgent.map((contract) => <Link key={contract.id} to={`/contracts/${contract.id}`} className="card-solid" style={{ padding: 13 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
              <div>
                <strong>{contract.orderNumber || contract.id}</strong>
                <div className="page-subtitle" style={{ margin: 0 }}>{safeText(contract.customerName || contract.customerPhone)}</div>
              </div>
              <StatusBadge status={contract.status} />
            </div>
          </Link>)}
        </div>
        <div style={{ marginTop: 16 }}>
          <Badge tone={openTickets.length ? 'orange' : 'green'}>{openTickets.length} تذاكر دعم مفتوحة</Badge>
        </div>
      </Card>
    </div>

    <div className="grid-2">
      <Card style={{ padding: 18 }}>
        <h2 className="section-title">العقود حسب المدينة</h2>
        <SimpleBarChart data={summary.byCity} xKey="city" yKey="count" />
      </Card>
      <Card style={{ padding: 18 }}>
        <h2 className="section-title">آخر عمليات السجل</h2>
        <div className="timeline">
          {query.data.auditLogs.slice(0, 8).map((log) => <div className="timeline-item" key={log.id}>
            <strong>{safeText(log.action)}</strong>
            <p className="page-subtitle" style={{ margin: '4px 0 0' }}>{safeText(log.actorName || log.actorEmail)} · {formatDate(log.createdAt)}</p>
          </div>)}
          {!query.data.auditLogs.length && <p className="page-subtitle">لم يتم تسجيل عمليات بعد.</p>}
        </div>
      </Card>
    </div>
  </div>;
}

function Kpi({ title, value, hint, tone }: { title: string; value: React.ReactNode; hint?: string; tone?: 'orange' | 'red' | 'green' | 'gold' }) {
  return <Card className="kpi-card" goldLine>
    <div className="kpi-label">{title}</div>
    <div className="kpi-value" style={{ color: tone === 'red' ? 'var(--danger)' : tone === 'orange' ? 'var(--warning)' : tone === 'green' ? 'var(--success)' : tone === 'gold' ? 'var(--gold-600)' : 'var(--navy-950)' }}>{value}</div>
    {hint && <div className="kpi-label" style={{ marginTop: 8 }}>{hint}</div>}
  </Card>;
}
