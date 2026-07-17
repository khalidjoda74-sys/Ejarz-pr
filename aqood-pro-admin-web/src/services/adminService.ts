import { doc, getDoc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { AdminUser } from '@/types/admin';
import { listRecent } from './baseService';

export async function getAdminUser(uid: string) {
  const snap = await getDoc(doc(db, 'adminUsers', uid));
  if (!snap.exists()) return null;
  return { uid: snap.id, ...(snap.data() as Record<string, unknown>) } as AdminUser;
}

export async function touchAdminLogin(uid: string) {
  await setDoc(doc(db, 'adminUsers', uid), { lastLoginAt: serverTimestamp() }, { merge: true });
}

export async function listAdmins() {
  return listRecent<AdminUser & { id: string }>('adminUsers', 80, 'createdAt');
}

export async function upsertAdmin(uid: string, data: Partial<AdminUser>) {
  await setDoc(doc(db, 'adminUsers', uid), { ...data, uid, updatedAt: serverTimestamp() }, { merge: true });
}

export async function setAdminActive(uid: string, active: boolean) {
  await updateDoc(doc(db, 'adminUsers', uid), { active, updatedAt: serverTimestamp() });
}
