import { Contract } from '@/types/contract';
import { AppUser } from '@/types/user';
import { Property } from '@/types/property';
import { SupportTicket } from '@/types/support';
import { listContracts } from './contractService';
import { listUsers } from './userService';
import { listProperties } from './propertyService';
import { listSupportTickets } from './supportService';

export interface GlobalSearchResult {
  type: 'contract' | 'user' | 'property' | 'support';
  title: string;
  subtitle: string;
  to: string;
  status?: string;
}

function contains(record: Record<string, unknown>, keys: string[], q: string) {
  const query = q.trim().toLowerCase();
  return keys.some((key) => String(record[key] ?? '').toLowerCase().includes(query));
}

export async function globalSearch(query: string): Promise<GlobalSearchResult[]> {
  if (query.trim().length < 2) return [];
  const [contracts, users, properties, tickets] = await Promise.all([
    listContracts(40).catch(() => [] as Contract[]),
    listUsers(40).catch(() => [] as AppUser[]),
    listProperties(40).catch(() => [] as Property[]),
    listSupportTickets(40).catch(() => [] as SupportTicket[]),
  ]);
  const contractResults = contracts
    .filter((c) => contains(c as Record<string, unknown>, ['id', 'orderNumber', 'customerName', 'customerPhone', 'city'], query))
    .slice(0, 5)
    .map((c) => ({ type: 'contract' as const, title: c.orderNumber || c.id, subtitle: c.customerName || c.customerPhone || 'عقد', to: `/contracts/${c.id}`, status: c.status }));
  const userResults = users
    .filter((u) => contains(u as Record<string, unknown>, ['uid', 'id', 'displayName', 'name', 'phone', 'email'], query))
    .slice(0, 5)
    .map((u) => ({ type: 'user' as const, title: u.displayName || u.name || u.phone || u.uid, subtitle: u.email || u.phone || 'مستخدم', to: `/users/${u.uid || u.id}` }));
  const propertyResults = properties
    .filter((p) => contains(p as Record<string, unknown>, ['id', 'title', 'ownerName', 'city', 'district'], query))
    .slice(0, 5)
    .map((p) => ({ type: 'property' as const, title: p.title || p.ownerName || p.id, subtitle: `${p.city ?? ''} ${p.district ?? ''}`.trim() || 'عقار', to: `/properties/${p.id}` }));
  const supportResults = tickets
    .filter((t) => contains(t as Record<string, unknown>, ['id', 'subject', 'message', 'userId', 'contractId'], query))
    .slice(0, 5)
    .map((t) => ({ type: 'support' as const, title: t.subject || t.id, subtitle: t.message || 'تذكرة دعم', to: `/support/${t.id}`, status: t.status }));
  return [...contractResults, ...userResults, ...propertyResults, ...supportResults].slice(0, 12);
}
