import { addDoc, collection, doc, getDoc, getDocs, limit, orderBy, query, serverTimestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { AppNotification } from '@/types/notification';
import { AdminUser } from '@/types/admin';
import { writeAuditLog } from './auditService';
import { cleanUndefined } from '@/lib/firebaseNormalizers';
import { Contract } from '@/types/contract';

type CreateNotificationInput = Omit<AppNotification, 'id' | 'createdAt' | 'createdBy' | 'uid' | 'userId'> & {
  uid?: string;
  userId?: string;
};

export async function listNotifications(count = 80) {
  const snap = await getDocs(query(collection(db, 'notifications'), orderBy('createdAt', 'desc'), limit(count)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as AppNotification);
}

export async function createNotification(admin: AdminUser, values: CreateNotificationInput) {
  const uid = await resolveUid(values);
  const contractId = String(values.contractId ?? '').trim() || undefined;
  const type = String(values.type ?? '').trim() || (contractId ? 'contractMessage' : 'general');
  const payload = cleanUndefined({
    ...values,
    uid,
    userId: uid,
    contractId,
    type,
    read: false,
    actionType: values.actionType ?? (contractId ? 'contractDetails' : undefined),
    actionPayload: values.actionPayload
      ? { ...values.actionPayload, ...(contractId ? { contractId } : {}) }
      : contractId ? { contractId } : undefined,
    channels: {
      inApp: true,
      push: type !== 'draftSaved',
      ...(values.channels ?? {}),
    },
    priority: values.priority ?? 'normal',
    delivery: {
      pushStatus: 'pending',
      error: '',
      ...(values.delivery ?? {}),
    },
    readAt: null,
    sentAt: null,
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

async function resolveUid(values: CreateNotificationInput) {
  const explicitUid = String(values.uid || values.userId || '').trim();
  const contractId = String(values.contractId ?? '').trim();
  if (!contractId) {
    if (!explicitUid) throw new Error('يجب إدخال UID المستخدم لإرسال الإشعار.');
    return explicitUid;
  }

  const snap = await getDoc(doc(db, 'contracts', contractId));
  if (!snap.exists()) {
    if (explicitUid) return explicitUid;
    throw new Error('لم يتم العثور على العقد، ولا يمكن استنتاج UID العميل.');
  }

  const contract = { id: snap.id, ...snap.data() } as Contract;
  const contractUid = String(contract.uid || contract.userId || '').trim();
  if (!contractUid && !explicitUid) {
    throw new Error('العقد لا يحتوي UID للعميل، أدخل UID المستخدم يدويًا.');
  }
  if (explicitUid && contractUid && explicitUid !== contractUid) {
    throw new Error('UID المدخل لا يطابق UID صاحب العقد.');
  }
  return explicitUid || contractUid;
}
