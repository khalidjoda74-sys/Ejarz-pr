import { safeText } from '@/lib/formatters';

export function InfoItem({ label, value }: { label: string; value: unknown }) {
  return <div className="info-item"><span>{label}</span><strong>{safeText(value)}</strong></div>;
}
