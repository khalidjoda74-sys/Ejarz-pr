import { addDoc, collection, getDocs, limit, orderBy, query, serverTimestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { AppNotification } from '@/types/notification';
import { AdminUser } from '@/types/admin';
import { writeAuditLog } from './auditService';
import { cleanUndefined } from '@/lib/firebaseNormalizers';

export async function listNotifications(count = 80) {
  const snap = await getDocs(query(collection(db, 'notifications'), orderBy('createdAt', 'desc'), limit(count)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as AppNotification);
}

export async function createNotification(admin: AdminUser, values: Omit<AppNotification, 'id' | 'createdAt' | 'createdBy'>) {
  const payload = cleanUndefined({
    ...values,
    delivery: values.delivery ?? { pushStatus: 'pending' },
    createdBy: admin.uid,
    createdAt: serverTimestamp(),
  });
  const ref = await addDoc(collection(db, 'notifications'), payload);
  await writeAuditLog(admin, {
    action: 'notification.create',
    entityType: 'notification',
    entityId: ref.id,
    after: payload,
    message: 'إنشاء إشعار من لوحة التحكم',
  });
  return ref.id;
}
