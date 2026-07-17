import { addDoc, collection, getDocs, limit, orderBy, query, serverTimestamp, updateDoc, doc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { AdminUser } from '@/types/admin';
import { Invoice, Payment } from '@/types/payment';
import { writeAuditLog } from './auditService';
import { cleanUndefined } from '@/lib/firebaseNormalizers';

export async function listPayments(count = 100) {
  const snap = await getDocs(query(collection(db, 'payments'), orderBy('createdAt', 'desc'), limit(count)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as Payment);
}

export async function listInvoices(count = 100) {
  const snap = await getDocs(query(collection(db, 'invoices'), orderBy('createdAt', 'desc'), limit(count)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as Invoice);
}

export async function createPaymentSkeleton(admin: AdminUser, payment: Omit<Payment, 'id' | 'createdAt'>) {
  const payload = cleanUndefined({ ...payment, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
  const ref = await addDoc(collection(db, 'payments'), payload);
  await writeAuditLog(admin, { action: 'payment.create', entityType: 'payment', entityId: ref.id, after: payload, message: 'إنشاء بنية دفعة جاهزة للربط' });
  return ref.id;
}

export async function updatePaymentStatus(admin: AdminUser, payment: Payment, status: Payment['status']) {
  await updateDoc(doc(db, 'payments', payment.id), { status, updatedAt: serverTimestamp() });
  await writeAuditLog(admin, { action: 'payment.status.update', entityType: 'payment', entityId: payment.id, before: { status: payment.status }, after: { status }, message: 'تحديث حالة دفعة' });
}
