import dayjs from 'dayjs';
import 'dayjs/locale/ar';

dayjs.locale('ar');

export function toDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value === 'string' || typeof value === 'number') {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (typeof value === 'object' && value !== null && 'toDate' in value && typeof (value as { toDate: () => Date }).toDate === 'function') {
    return (value as { toDate: () => Date }).toDate();
  }
  return null;
}

export function formatDate(value: unknown, fallback = 'غير متوفر') {
  const d = toDate(value);
  if (!d) return fallback;
  return dayjs(d).format('D MMMM YYYY - h:mm A');
}

export function formatShortDate(value: unknown, fallback = 'غير متوفر') {
  const d = toDate(value);
  if (!d) return fallback;
  return dayjs(d).format('D MMM YYYY');
}

export function isToday(value: unknown) {
  const d = toDate(value);
  if (!d) return false;
  return dayjs(d).isSame(dayjs(), 'day');
}

export function inRange(value: unknown, from?: string, to?: string) {
  const d = toDate(value);
  if (!d) return false;
  const current = dayjs(d);
  if (from && current.isBefore(dayjs(from), 'day')) return false;
  if (to && current.isAfter(dayjs(to), 'day')) return false;
  return true;
}
