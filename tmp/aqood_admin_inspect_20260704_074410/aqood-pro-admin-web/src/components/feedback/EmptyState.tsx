import { Button } from '@/components/ui/Button';

export function EmptyState({ title = 'لا توجد بيانات', description = 'لم يتم العثور على سجلات مطابقة.', actionLabel, onAction }: { title?: string; description?: string; actionLabel?: string; onAction?: () => void }) {
  return <div className="card-solid" style={{ padding: 24, textAlign: 'center' }}>
    <div className="brand-mark" style={{ margin: '0 auto 12px', transform: 'scale(.82)' }}>◇</div>
    <h3 style={{ margin: 0 }}>{title}</h3>
    <p className="page-subtitle" style={{ marginBottom: actionLabel ? 16 : 0 }}>{description}</p>
    {actionLabel && <Button variant="gold" onClick={onAction}>{actionLabel}</Button>}
  </div>;
}
