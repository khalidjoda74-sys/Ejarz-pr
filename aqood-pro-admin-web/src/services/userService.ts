import { collection, doc, getDocs, limit, orderBy, query, serverTimestamp, updateDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { AdminUser } from '@/types/admin';
import { AppUser, FcmToken } from '@/types/user';
import { Contract } from '@/types/contract';
import { Property } from '@/types/property';
import { getDocument, listCollection } from './baseService';
import { writeAuditLog } from './auditService';

export async function listUsers(count = 120) {
  const snap = await getDocs(query(collection(db, 'users'), orderBy('createdAt', 'desc'), limit(count)));
  return snap.docs.map((d) => ({ uid: d.id, id: d.id, ...d.data() }) as AppUser);
}

export async function getUser(uid: string) {
  return getDocument<AppUser & { id: string }>('users', uid);
}

export async function listUserFcmTokens(uid: string) {
  return listCollection<FcmToken>(`users/${uid}/fcmTokens`);
}

export async function listUserContracts(uid: string) {
  const all = await listCollection<Contract>('contracts', [limit(120)]);
  return all.filter((contract) => contract.userId === uid || contract.uid === uid);
}

export async function listUserProperties(uid: string) {
  const all = await listCollection<Property>('properties', [limit(120)]);
  return all.filter((property) => property.uid === uid || property.userId === uid);
}

export async function setUserBlocked(admin: AdminUser, user: AppUser, blocked: boolean, reason?: string) {
  if (blocked && !String(reason ?? '').trim()) {
    throw new Error('اكتب سبب إيقاف الحساب ليظهر للمستخدم.');
  }
  const payload = {
    status: blocked ? 'blocked' : 'active',
    blocked,
    blockedAt: blocked ? serverTimestamp() : null,
    blockedBy: blocked ? admin.uid : '',
    blockReason: blocked ? reason ?? '' : '',
    updatedAt: serverTimestamp(),
  };
  await updateDoc(doc(db, 'users', user.uid || user.id || ''), payload);
  await writeAuditLog(admin, {
    action: blocked ? 'user.block' : 'user.unblock',
    entityType: 'user',
    entityId: user.uid || user.id,
    before: { blocked: user.blocked, status: user.status },
    after: payload,
    message: blocked ? 'حظر مستخدم' : 'فك حظر مستخدم',
  });
}
