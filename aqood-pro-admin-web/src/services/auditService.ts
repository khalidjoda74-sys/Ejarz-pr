import { addDoc, collection, getDocs, limit, orderBy, query, serverTimestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { AuditEntityType } from '@/types/audit';
import { AdminUser } from '@/types/admin';

export interface AuditInput {
  action: string;
  entityType: AuditEntityType;
  entityId?: string;
  before?: unknown;
  after?: unknown;
  message?: string;
}

export async function writeAuditLog(admin: AdminUser | null | undefined, input: AuditInput) {
  if (!admin) return;
  await addDoc(collection(db, 'auditLogs'), {
    actorUid: admin.uid,
    actorEmail: admin.email ?? '',
    actorName: admin.displayName ?? '',
    action: input.action,
    entityType: input.entityType,
    entityId: input.entityId ?? '',
    before: input.before ?? null,
    after: input.after ?? null,
    message: input.message ?? '',
    createdAt: serverTimestamp(),
    source: 'admin-web',
  });
}


export async function listAuditLogs(count = 120) {
  const snap = await getDocs(query(collection(db, 'auditLogs'), orderBy('createdAt', 'desc'), limit(count)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as import('@/types/audit').AuditLog);
}
