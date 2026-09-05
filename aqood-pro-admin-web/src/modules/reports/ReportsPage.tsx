import { useMemo, useState } from 'react';
import { contractAmount } from '@/lib/contractPricing';
import { PageHeader } from '@/components/layout/PageHeader';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Field, Input } from '@/components/ui/Field';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { ErrorState } from '@/components/feedback/ErrorState';
import { KpiSkeleton } from '@/components/feedback/Skeletons';
import { StatusPie, SimpleBarChart } from '@/components/charts/Charts';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import { listContracts } from '@/services/contractService';
import { listUsers } from '@/services/userService';
import { filterByDateRange, newUsersByDay, summarizeContracts, summarizeUsers } from '@/services/reportService';
import { exportCsv } from '@/lib/csv';
import { formatCurrency } from '@/lib/formatters';

export function ReportsPage() {
  const { data, loading, error, refresh } = useFirestoreQuery(async () => {
    const [contracts, users] = await Promise.all([listContracts(220), listUsers(180)]);
    return { contracts, users };
  }, []);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const filteredContracts = useMemo(() => filterByDateRange(data?.contracts ?? [], from, to), [data, from, to]);
  const filteredUsers = useMemo(() => filterByDateRange(data?.users ?? [], from, to), [data, from, to]);
  const summary = useMemo(() => summarizeContracts(filteredContracts), [filteredContracts]);
  const userSummary = useMemo(() => summarizeUsers(filteredUsers), [filteredUsers]);
  const missingReport = filteredContracts.filter((contract) => contract.missingItems?.some((item) => item.status === 'open')).map((contract) => ({ orderNumber: contract.orderNumber || contract.id, customer: contract.customerName, missingCount: contract.missingItems?.filter((item) => item.status === 'open').length ?? 0 }));
  const adminReport = Object.entries(filteredContracts.reduce<Record<string, number>>((acc, contract) => { const name = contract.assignedAdminName || 'غير معين'; acc[name] = (acc[name] ?? 0) + 1; return acc; }, {})).map(([admin, count]) => ({ admin, count }));

  if (loading) return <><PageHeader title="التقارير" subtitle="جاري تحميل تقارير Firebase." /><KpiSkeleton /></>;
  if (error) return <ErrorState message={error} onRetry={refresh} />;

  return <div className="stack"><PageHeader title="التقارير" subtitle="تقارير العقود والإيرادات والنواقص والمستخدمين مع تصدير CSV." actions={<><Button variant="soft" onClick={refresh}>تحديث</Button><Button variant="gold" onClick={() => exportCsv('contracts-report.csv', filteredContracts.map((c) => ({ id: c.id, orderNumber: c.orderNumber, status: c.status, customerName: c.customerName, city: c.city, totalPayable: contractAmount(c) })))}>تصدير تقرير العقود</Button></>} />
    <div className="card" style={{ padding: 14 }}><div className="filters-bar" style={{ gridTemplateColumns: '1fr 1fr auto' }}><Field label="من تاريخ"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field><Field label="إلى تاريخ"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field><Button variant="soft" style={{ alignSelf: 'end' }} onClick={() => { setFrom(''); setTo(''); }}>مسح</Button></div></div>
    <div className="kpi-grid"><Kpi title="العقود" value={summary.total} /><Kpi title="المكتملة" value={summary.completed} /><Kpi title="مستخدمون جدد" value={userSummary.total} /><Kpi title="الإيرادات" value={formatCurrency(summary.totalFees)} /></div>
    <div className="grid-2"><Card style={{ padding: 18 }}><h2 className="section-title">العقود حسب الحالة</h2><StatusPie data={summary.byStatus} /></Card><Card style={{ padding: 18 }}><h2 className="section-title">العقود حسب المدينة</h2><SimpleBarChart data={summary.byCity} xKey="city" yKey="count" /></Card></div>
    <div className="grid-2"><Card style={{ padding: 18 }}><h2 className="section-title">المستخدمون الجدد</h2><SimpleBarChart data={newUsersByDay(filteredUsers)} xKey="day" yKey="count" /></Card><Card style={{ padding: 18 }}><h2 className="section-title">الأداء حسب الأدمن</h2><SimpleBarChart data={adminReport} xKey="admin" yKey="count" /></Card></div>
    <Card style={{ padding: 18 }}><div style={{ display:'flex', justifyContent:'space-between', gap:12 }}><h2 className="section-title">تقرير النواقص</h2><Button variant="soft" onClick={() => exportCsv('missing-items-report.csv', missingReport)}>تصدير النواقص</Button></div><div className="stack">{missingReport.map((row) => <div className="card-solid" style={{ padding: 12 }} key={row.orderNumber}><strong>{row.orderNumber}</strong> <Badge tone="red">{row.missingCount} نقص مفتوح</Badge></div>)}{!missingReport.length && <p className="page-subtitle">لا توجد نواقص مفتوحة في الفترة المحددة.</p>}</div></Card>
  </div>;
}
function Kpi({ title, value }: { title: string; value: React.ReactNode }) { return <Card className="kpi-card"><div className="kpi-label">{title}</div><div className="kpi-value">{value}</div></Card>; }
