import { Bar, BarChart, CartesianGrid, Cell, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { CONTRACT_STATUS_LABELS, ContractStatus } from '@/types/contract';

const palette = ['#071A2D', '#0B2742', '#C9A227', '#E6C76A', '#16A34A', '#F59E0B', '#DC2626', '#64748B', '#4F46E5'];

export function StatusPie({ data }: { data: Array<{ status: string; count: number }> }) {
  const chartData = data.map((item) => ({ name: CONTRACT_STATUS_LABELS[item.status as ContractStatus] ?? item.status, value: item.count })).filter((item) => item.value > 0);
  if (!chartData.length) return <p className="page-subtitle">لا توجد بيانات كافية للرسم.</p>;
  return <ResponsiveContainer width="100%" height={260}>
    <PieChart>
      <Pie data={chartData} dataKey="value" nameKey="name" innerRadius={52} outerRadius={92} paddingAngle={3}>
        {chartData.map((_, index) => <Cell key={index} fill={palette[index % palette.length]} />)}
      </Pie>
      <Tooltip />
    </PieChart>
  </ResponsiveContainer>;
}

export function SimpleBarChart({ data, xKey, yKey }: { data: Record<string, unknown>[]; xKey: string; yKey: string }) {
  if (!data.length) return <p className="page-subtitle">لا توجد بيانات كافية للرسم.</p>;
  return <ResponsiveContainer width="100%" height={260}>
    <BarChart data={data} margin={{ top: 10, right: 0, left: 0, bottom: 10 }}>
      <CartesianGrid strokeDasharray="3 3" vertical={false} />
      <XAxis dataKey={xKey} tick={{ fontSize: 12 }} />
      <YAxis tick={{ fontSize: 12 }} allowDecimals={false} />
      <Tooltip />
      <Bar dataKey={yKey} radius={[12, 12, 0, 0]} fill="#C9A227" />
    </BarChart>
  </ResponsiveContainer>;
}
