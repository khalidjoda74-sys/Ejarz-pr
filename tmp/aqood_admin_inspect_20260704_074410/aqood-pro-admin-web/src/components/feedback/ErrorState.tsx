import { Button } from '@/components/ui/Button';

export function ErrorState({ message, onRetry }: { message?: string | null; onRetry?: () => void }) {
  return <div className="card-solid" style={{ padding: 24 }}>
    <BadgeLike />
    <h3 style={{ margin: '10px 0 6px' }}>تعذر تحميل البيانات</h3>
    <p className="page-subtitle">{message || 'حدث خطأ غير متوقع.'}</p>
    {onRetry && <Button variant="soft" onClick={onRetry}>إعادة المحاولة</Button>}
  </div>;
}

function BadgeLike() {
  return <span className="badge badge-red">خطأ</span>;
}
