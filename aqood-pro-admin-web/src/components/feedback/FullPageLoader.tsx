export function FullPageLoader({ label = 'جاري التحميل' }: { label?: string }) {
  return <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: 24 }}>
    <div className="card" style={{ padding: 28, textAlign: 'center', width: 'min(420px, 100%)' }}>
      <div className="brand-mark" style={{ margin: '0 auto 14px' }}>عق</div>
      <h2 style={{ margin: 0 }}>عقود برو</h2>
      <p className="page-subtitle">{label}</p>
      <div className="skeleton" style={{ height: 10, marginTop: 18 }} />
    </div>
  </div>;
}
