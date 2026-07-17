import { Button } from '@/components/ui/Button';

export function ConfirmDialog({
  open,
  title,
  description,
  confirmLabel = 'تأكيد',
  danger,
  onConfirm,
  onCancel,
}: {
  open: boolean;
  title: string;
  description?: string;
  confirmLabel?: string;
  danger?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  if (!open) return null;
  return <>
    <div className="modal-backdrop" onClick={onCancel} />
    <div className="modal-panel">
      <span className={`badge ${danger ? 'badge-red' : 'badge-gold'}`}>{danger ? 'إجراء حساس' : 'تأكيد'}</span>
      <h3 style={{ margin: '12px 0 8px' }}>{title}</h3>
      {description && <p className="page-subtitle">{description}</p>}
      <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', marginTop: 18 }}>
        <Button variant="soft" onClick={onCancel}>إلغاء</Button>
        <Button variant={danger ? 'danger' : 'gold'} onClick={onConfirm}>{confirmLabel}</Button>
      </div>
    </div>
  </>;
}
