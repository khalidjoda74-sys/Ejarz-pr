import {
  arrayUnion,
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { AdminUser } from '@/types/admin';
import { Contract, ContractFile, ContractStatus, InternalNote, MissingItem } from '@/types/contract';
import { writeAuditLog } from './auditService';

export async function listContracts(count = 120) {
  const snap = await getDocs(query(collection(db, 'contracts'), orderBy('createdAt', 'desc'), limit(count)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as Contract);
}

export async function getContract(contractId: string) {
  const snap = await getDoc(doc(db, 'contracts', contractId));
  if (!snap.exists()) return null;
  return { id: snap.id, ...snap.data() } as Contract;
}

export async function listContractFiles(contractId: string) {
  const snap = await getDocs(query(collection(db, `contracts/${contractId}/files`), orderBy('uploadedAt', 'desc'), limit(100)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as ContractFile);
}

export async function updateContractStatus(admin: AdminUser, contract: Contract, status: ContractStatus, customerNote?: string) {
  const batch = writeBatch(db);
  const contractRef = doc(db, 'contracts', contract.id);
  const timelineItem = {
    id: crypto.randomUUID(),
    title: `تغيير الحالة إلى ${status}`,
    description: customerNote ?? '',
    status,
    createdAt: new Date().toISOString(),
    createdBy: admin.uid,
  };
  batch.update(contractRef, {
    status,
    customerNote: customerNote ?? contract.customerNote ?? '',
    timeline: arrayUnion(timelineItem),
    updatedAt: serverTimestamp(),
  });
  if (contract.userId || contract.uid) {
    const notificationRef = doc(collection(db, 'notifications'));
    batch.set(notificationRef, {
      userId: contract.userId ?? contract.uid,
      contractId: contract.id,
      title: 'تحديث حالة العقد',
      body: customerNote || `تم تحديث حالة العقد إلى ${status}`,
      priority: 'high',
      actionType: 'contractDetails',
      actionPayload: { contractId: contract.id },
      read: false,
      delivery: { pushStatus: 'pending' },
      createdAt: serverTimestamp(),
      createdBy: admin.uid,
    });
  }
  const auditRef = doc(collection(db, 'auditLogs'));
  batch.set(auditRef, {
    actorUid: admin.uid,
    actorEmail: admin.email ?? '',
    actorName: admin.displayName ?? '',
    action: 'contract.status.update',
    entityType: 'contract',
    entityId: contract.id,
    before: { status: contract.status },
    after: { status, customerNote },
    message: 'تغيير حالة عقد من لوحة التحكم',
    createdAt: serverTimestamp(),
    source: 'admin-web',
  });
  await batch.commit();
}

export async function addMissingItem(admin: AdminUser, contractId: string, item: Omit<MissingItem, 'id' | 'createdAt' | 'createdBy' | 'status'>) {
  const missingItem: MissingItem = {
    ...item,
    id: crypto.randomUUID(),
    status: 'open',
    createdAt: new Date().toISOString(),
    createdBy: admin.uid,
  };
  await updateDoc(doc(db, 'contracts', contractId), {
    missingItems: arrayUnion(missingItem),
    status: 'missingData',
    updatedAt: serverTimestamp(),
  });
  await writeAuditLog(admin, { action: 'contract.missing.add', entityType: 'contract', entityId: contractId, after: missingItem, message: 'إضافة نقص مطلوب' });
}

export async function addInternalNote(admin: AdminUser, contractId: string, note: string) {
  const internalNote: InternalNote = {
    id: crypto.randomUUID(),
    note,
    createdAt: new Date().toISOString(),
    createdBy: admin.uid,
    createdByName: admin.displayName ?? admin.email ?? 'أدمن',
  };
  await updateDoc(doc(db, 'contracts', contractId), {
    internalNotes: arrayUnion(internalNote),
    updatedAt: serverTimestamp(),
  });
  await writeAuditLog(admin, { action: 'contract.note.add', entityType: 'contract', entityId: contractId, after: internalNote, message: 'إضافة ملاحظة داخلية' });
}

export async function assignContractAdmin(admin: AdminUser, contractId: string, assignedAdmin: AdminUser) {
  await updateDoc(doc(db, 'contracts', contractId), {
    assignedAdminUid: assignedAdmin.uid,
    assignedAdminName: assignedAdmin.displayName ?? assignedAdmin.email ?? assignedAdmin.uid,
    updatedAt: serverTimestamp(),
  });
  await writeAuditLog(admin, {
    action: 'contract.assignAdmin',
    entityType: 'contract',
    entityId: contractId,
    after: { assignedAdminUid: assignedAdmin.uid },
    message: 'تعيين أدمن مسؤول عن العقد',
  });
}

export async function markFinalPdfUploaded(admin: AdminUser, contract: Contract, fileName: string, fileUrl: string) {
  const batch = writeBatch(db);
  const contractRef = doc(db, 'contracts', contract.id);
  batch.update(contractRef, {
    finalPdfUrl: fileUrl,
    finalPdfFileName: fileName,
    finalPdfUploadedAt: serverTimestamp(),
    finalPdfUploadedBy: admin.uid,
    status: 'authenticated',
    updatedAt: serverTimestamp(),
  });
  if (contract.userId || contract.uid) {
    const notificationRef = doc(collection(db, 'notifications'));
    batch.set(notificationRef, {
      userId: contract.userId ?? contract.uid,
      contractId: contract.id,
      title: 'تم اعتماد العقد',
      body: 'تم رفع ملف العقد النهائي وأصبح جاهزًا للاطلاع.',
      priority: 'high',
      actionType: 'contractDetails',
      actionPayload: { contractId: contract.id },
      read: false,
      delivery: { pushStatus: 'pending' },
      createdAt: serverTimestamp(),
      createdBy: admin.uid,
    });
  }
  const auditRef = doc(collection(db, 'auditLogs'));
  batch.set(auditRef, {
    actorUid: admin.uid,
    actorEmail: admin.email ?? '',
    actorName: admin.displayName ?? '',
    action: 'contract.finalPdf.upload',
    entityType: 'contract',
    entityId: contract.id,
    before: { status: contract.status, finalPdfUrl: contract.finalPdfUrl ?? null },
    after: { status: 'authenticated', finalPdfFileName: fileName, finalPdfUrl: fileUrl },
    message: 'رفع ملف PDF النهائي وتحويل العقد إلى مكتمل',
    createdAt: serverTimestamp(),
    source: 'admin-web',
  });
  await batch.commit();
}
