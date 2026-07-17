export function KpiSkeleton() {
  return <div className="kpi-grid">{Array.from({ length: 8 }).map((_, index) => <div key={index} className="card kpi-card"><div className="skeleton" style={{ height: 18, width: '60%' }} /><div className="skeleton" style={{ height: 34, width: '40%', marginTop: 18 }} /></div>)}</div>;
}

export function TableSkeleton({ rows = 6 }: { rows?: number }) {
  return <div className="card-solid" style={{ padding: 12 }}>{Array.from({ length: rows }).map((_, index) => <div key={index} className="skeleton" style={{ height: 52, margin: 8 }} />)}</div>;
}
