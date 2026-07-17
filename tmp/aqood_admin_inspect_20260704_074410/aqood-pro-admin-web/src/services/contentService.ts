import { doc, getDoc, serverTimestamp, setDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { AdminUser } from '@/types/admin';
import { AppContentConfig, DEFAULT_LEGAL_LINKS } from '@/types/content';
import { writeAuditLog } from './auditService';

export async function getAppContentConfig() {
  const snap = await getDoc(doc(db, 'appContent', 'config'));
  if (!snap.exists()) return { legalLinks: DEFAULT_LEGAL_LINKS } as AppContentConfig;
  const data = snap.data() as AppContentConfig;
  return { ...data, legalLinks: { ...DEFAULT_LEGAL_LINKS, ...(data.legalLinks ?? {}) } };
}

export async function updateAppContentConfig(admin: AdminUser, before: AppContentConfig, patch: Partial<AppContentConfig>) {
  await setDoc(doc(db, 'appContent', 'config'), { ...patch, updatedAt: serverTimestamp(), updatedBy: admin.uid }, { merge: true });
  await writeAuditLog(admin, { action: 'content.config.update', entityType: 'content', entityId: 'config', before: before as Record<string, unknown>, after: patch as Record<string, unknown>, message: 'تحديث محتوى التطبيق' });
}
