import { CONTRACT_STATUS_LABELS, ContractStatus } from '@/types/contract';
import { ADMIN_ROLE_LABELS, AdminRole } from '@/types/admin';

export function safeText(value: unknown, fallback = 'غير متوفر') {
  if (value === null || value === undefined || value === '') return fallback;
  if (typeof value === 'boolean') return value ? 'نعم' : 'لا';
  if (typeof value === 'object') return fallback;
  return String(value);
}

export function safeNumber(value: unknown, fallback = 0) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function formatCurrency(value: unknown) {
  return new Intl.NumberFormat('ar-SA', { style: 'currency', currency: 'SAR', maximumFractionDigits: 0 }).format(safeNumber(value));
}

export function statusLabel(status?: string) {
  if (!status) return 'غير محدد';
  return CONTRACT_STATUS_LABELS[status as ContractStatus] ?? status;
}

export function roleLabel(role?: string) {
  if (!role) return 'غير محدد';
  return ADMIN_ROLE_LABELS[role as AdminRole] ?? role;
}

export function initials(name?: string | null) {
  if (!name) return 'عق';
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join('')
    .toUpperCase();
}

export function getRecordValue(record: unknown, keys: string[], fallback = 'غير متوفر') {
  if (!record || typeof record !== 'object') return fallback;
  const obj = record as Record<string, unknown>;
  for (const key of keys) {
    if (obj[key] !== undefined && obj[key] !== null && obj[key] !== '') return safeText(obj[key]);
  }
  return fallback;
}
