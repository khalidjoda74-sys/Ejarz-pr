import { arrayUnion, collection, doc, getDoc, getDocs, limit, orderBy, query, serverTimestamp, updateDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { AdminUser } from '@/types/admin';
import { SupportReply, SupportTicket, SupportTicketStatus } from '@/types/support';
import { writeAuditLog } from './auditService';

export async function listSupportTickets(count = 100) {
  const snap = await getDocs(query(collection(db, 'supportTickets'), orderBy('createdAt', 'desc'), limit(count)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as SupportTicket);
}

export async function getSupportTicket(id: string) {
  const snap = await getDoc(doc(db, 'supportTickets', id));
  if (!snap.exists()) return null;
  return { id: snap.id, ...snap.data() } as SupportTicket;
}

export async function addSupportReply(admin: AdminUser, ticketId: string, message: string, visibility: 'admin' | 'customer' = 'customer') {
  const reply: SupportReply = {
    id: crypto.randomUUID(),
    message,
    visibility,
    createdAt: new Date().toISOString(),
    createdBy: admin.uid,
    createdByName: admin.displayName ?? admin.email ?? 'أدمن',
  };
  const patch: Record<string, unknown> = { replies: arrayUnion(reply), updatedAt: serverTimestamp() };
  if (visibility === 'customer') patch.status = 'pending';
  await updateDoc(doc(db, 'supportTickets', ticketId), patch);
  await writeAuditLog(admin, { action: 'support.reply.add', entityType: 'supportTicket', entityId: ticketId, after: reply, message: 'إضافة رد على تذكرة دعم' });
}

export async function updateTicketStatus(admin: AdminUser, ticket: SupportTicket, status: SupportTicketStatus) {
  await updateDoc(doc(db, 'supportTickets', ticket.id), { status, updatedAt: serverTimestamp() });
  await writeAuditLog(admin, { action: 'support.status.update', entityType: 'supportTicket', entityId: ticket.id, before: { status: ticket.status }, after: { status }, message: 'تغيير حالة تذكرة دعم' });
}
