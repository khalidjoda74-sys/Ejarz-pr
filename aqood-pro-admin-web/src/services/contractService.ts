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
  where,
  writeBatch,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { AdminUser } from '@/types/admin';
import {
  Contract,
  ContractFile,
  ContractStatus,
  CONTRACT_STATUSES,
  InternalNote,
  MissingRequirement,
  MissingRequirementResponse,
} from '@/types/contract';
import { writeAuditLog } from './auditService';

type MissingRequirementInput = Pick<MissingRequirement, 'title' | 'description' | 'type' | 'fieldPath'>;

export async function listContracts(count = 120) {
  const snap = await getDocs(query(collection(db, 'contracts'), orderBy('createdAt', 'desc'), limit(count)));
  return snap.docs.map((d) => normalizeContract({ id: d.id, ...d.data() }));
}

export async function getContract(contractId: string) {
  const snap = await getDoc(doc(db, 'contracts', contractId));
  if (!snap.exists()) return null;
  return normalizeContract({ id: snap.id, ...snap.data() });
}

export async function listContractFiles(contractId: string) {
  const snap = await getDocs(query(collection(db, `contracts/${contractId}/files`), orderBy('uploadedAt', 'desc'), limit(100)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as ContractFile);
}

export async function listMissingRequirementResponses(contractId: string) {
  const snap = await getDocs(query(collection(db, `contracts/${contractId}/missingResponses`), orderBy('createdAt', 'desc'), limit(100)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as MissingRequirementResponse);
}

export async function updateContractStatus(
  admin: AdminUser,
  contract: Contract,
  status: ContractStatus,
  customerVisibleNote = '',
) {
  const batch = writeBatch(db);
  const contractRef = doc(db, 'contracts', contract.id);
  const note = customerVisibleNote.trim();
  const timelineItem = timelineEventFor(status, note);
  const patch: Record<string, unknown> = {
    status,
    customerVisibleNote: note,
    timeline: arrayUnion(timelineItem),
    updatedAt: serverTimestamp(),
  };
  if (status === 'authenticated') patch.completedAt = serverTimestamp();
  if (status === 'awaitingPayment') {
    patch.totalFees = 398;
    patch.totalPayable = 398;
    patch.ejarPlatformFee = 299;
    patch.serviceFee = 99;
  }

  batch.update(contractRef, patch);

  const uid = contractUid(contract);
  if (status === 'awaitingPayment' && uid) {
    await ensurePendingPaymentArtifacts(batch, contract, uid);
  }

  if (uid) {
    batch.set(doc(collection(db, 'notifications')), notificationData({
      uid,
      contractId: contract.id,
      title: timelineItem.title,
      body: notificationBodyForStatus(status, note),
      type: notificationTypeForStatus(status),
      priority: ['awaitingPayment', 'authenticated', 'rejected'].includes(status) ? 'high' : 'normal',
      adminUid: admin.uid,
    }));
  }

  batch.set(doc(collection(db, 'auditLogs')), auditData(admin, {
    action: 'contract.status.update',
    entityId: contract.id,
    before: { status: contract.status, customerVisibleNote: contract.customerVisibleNote ?? '' },
    after: { status, customerVisibleNote: note },
    message: 'تغيير حالة عقد من لوحة التحكم',
  }));

  await batch.commit();
}

export async function addMissingItem(
  admin: AdminUser,
  contract: Contract,
  item: MissingRequirementInput,
) {
  const description = (item.description ?? '').trim();
  const missingRequirement: MissingRequirement = {
    id: crypto.randomUUID(),
    title: item.title.trim(),
    description,
    type: item.type || 'field',
    fieldPath: item.fieldPath?.trim() ?? '',
    required: true,
    resolved: false,
  };
  const timelineItem = timelineEventFor('missingData', description || missingRequirement.title);
  const batch = writeBatch(db);
  const contractRef = doc(db, 'contracts', contract.id);

  batch.update(contractRef, {
    status: 'missingData',
    customerVisibleNote: description || missingRequirement.title,
    missingRequirements: arrayUnion(missingRequirement),
    timeline: arrayUnion(timelineItem),
    updatedAt: serverTimestamp(),
  });

  const uid = contractUid(contract);
  if (uid) {
    batch.set(doc(collection(db, 'notifications')), notificationData({
      uid,
      contractId: contract.id,
      title: 'يوجد نقص مطلوب في طلبك',
      body: description || missingRequirement.title,
      type: 'missingRequirement',
      priority: 'high',
      adminUid: admin.uid,
    }));
  }

  batch.set(doc(collection(db, 'auditLogs')), auditData(admin, {
    action: 'contract.missing.add',
    entityId: contract.id,
    after: missingRequirement,
    message: 'إضافة نقص مطلوب',
  }));

  await batch.commit();
}

export async function setMissingRequirementResolved(
  admin: AdminUser,
  contract: Contract,
  requirementId: string,
  resolved = true,
) {
  const current = contract.missingRequirements ?? [];
  const next = current.map((item) => item.id === requirementId ? { ...item, resolved } : item);
  const allResolved = next.length > 0 && next.every((item) => item.resolved === true);
  const patch: Record<string, unknown> = {
    missingRequirements: next,
    updatedAt: serverTimestamp(),
  };
  if (allResolved && contract.status === 'missingData') {
    patch.status = 'processing';
    patch.customerVisibleNote = '?? ?????? ??????? ???????? ????? ???? ??? ????????.';
    patch.timeline = arrayUnion(timelineEventFor('processing', '?? ?????? ??????? ??????? ?? ??????.'));
  }
  await updateDoc(doc(db, 'contracts', contract.id), patch);
  await writeAuditLog(admin, {
    action: 'contract.missing.resolve',
    entityType: 'contract',
    entityId: contract.id,
    after: { requirementId, resolved },
    message: '?????? ??????? ??? ?? ??????',
  });
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

export async function markFinalPdfUploaded(
  admin: AdminUser,
  contract: Contract,
  fileName: string,
  fileUrl: string,
  storagePath = '',
) {
  const batch = writeBatch(db);
  const contractRef = doc(db, 'contracts', contract.id);
  const fileRef = doc(collection(db, `contracts/${contract.id}/files`));
  const timelineItem = timelineEventFor('authenticated', 'تم إصدار العقد النهائي ويمكن للعميل تحميله من التطبيق.');

  batch.update(contractRef, {
    finalPdfUrl: fileUrl,
    finalPdfFileName: fileName,
    finalPdfUploadedAt: serverTimestamp(),
    finalPdfUploadedBy: admin.uid,
    completedAt: serverTimestamp(),
    status: 'authenticated',
    timeline: arrayUnion(timelineItem),
    updatedAt: serverTimestamp(),
  });

  batch.set(fileRef, {
    fileType: 'finalPdf',
    title: 'العقد النهائي',
    fileName,
    storagePath,
    downloadUrl: fileUrl,
    url: fileUrl,
    uploadedBy: 'admin',
    adminUid: admin.uid,
    status: 'active',
    required: false,
    createdAt: serverTimestamp(),
    uploadedAt: serverTimestamp(),
  });

  const uid = contractUid(contract);
  if (uid) {
    batch.set(doc(collection(db, 'notifications')), notificationData({
      uid,
      contractId: contract.id,
      title: 'تم إصدار العقد النهائي',
      body: 'يمكنك الآن تحميل ملف العقد النهائي من تفاصيل الطلب.',
      type: 'finalPdfUploaded',
      priority: 'high',
      adminUid: admin.uid,
    }));
  }

  batch.set(doc(collection(db, 'auditLogs')), auditData(admin, {
    action: 'contract.finalPdf.upload',
    entityId: contract.id,
    before: { status: contract.status, finalPdfUrl: contract.finalPdfUrl ?? null },
    after: { status: 'authenticated', finalPdfFileName: fileName, finalPdfUrl: fileUrl, storagePath },
    message: 'رفع ملف PDF النهائي وتحويل العقد إلى مكتمل',
  }));

  await batch.commit();
}

function contractUid(contract: Contract) {
  return String(contract.uid || contract.userId || '').trim();
}

async function ensurePendingPaymentArtifacts(batch: ReturnType<typeof writeBatch>, contract: Contract, uid: string) {
  const [paymentsSnap, invoicesSnap] = await Promise.all([
    getDocs(query(collection(db, 'payments'), where('contractId', '==', contract.id), limit(1))),
    getDocs(query(collection(db, 'invoices'), where('contractId', '==', contract.id), limit(1))),
  ]);

  if (paymentsSnap.empty) {
    batch.set(doc(collection(db, 'payments')), {
      uid,
      userId: uid,
      contractId: contract.id,
      amount: 398,
      currency: 'SAR',
      method: 'notSelected',
      status: 'pending',
      provider: 'notConfigured',
      providerReference: '',
      ejarPlatformFee: 299,
      serviceFee: 99,
      totalPayable: 398,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
  }

  if (invoicesSnap.empty) {
    batch.set(doc(collection(db, 'invoices')), {
      uid,
      userId: uid,
      contractId: contract.id,
      invoiceNumber: invoiceNumberFor(contract),
      amount: 398,
      currency: 'SAR',
      status: 'pending',
      pdfUrl: '',
      items: [
        { title: 'رسوم منصة إيجار', amount: 299 },
        { title: 'عمولة عقود برو', amount: 99 },
      ],
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
  }
}

function invoiceNumberFor(contract: Contract) {
  const raw = String(contract.requestNumber || contract.orderNumber || contract.id).replace(/[^A-Za-z0-9-]/g, '');
  return `INV-${raw || contract.id}`;
}

function timelineEventFor(status: ContractStatus, note = '') {
  const now = new Date();
  return {
    id: crypto.randomUUID(),
    title: timelineTitleForStatus(status),
    subtitle: note || statusLabelForStatus(status),
    date: formatDateLabel(now),
    time: formatTimeLabel(now),
    completed: status === 'authenticated',
    current: status !== 'authenticated',
    status,
    createdAt: now.toISOString(),
  };
}

function notificationData({
  uid,
  contractId,
  title,
  body,
  type,
  priority,
  adminUid,
}: {
  uid: string;
  contractId: string;
  title: string;
  body: string;
  type: string;
  priority: 'normal' | 'high' | 'low';
  adminUid: string;
}) {
  return {
    uid,
    userId: uid,
    contractId,
    title,
    body,
    type,
    read: false,
    actionType: 'contractDetails',
    actionPayload: { contractId },
    channels: {
      inApp: true,
      push: type !== 'draftSaved',
    },
    priority,
    delivery: {
      pushStatus: 'pending',
      error: '',
    },
    createdAt: serverTimestamp(),
    readAt: null,
    sentAt: null,
    createdBy: adminUid,
  };
}

function auditData(admin: AdminUser, input: {
  action: string;
  entityId: string;
  before?: unknown;
  after?: unknown;
  message: string;
}) {
  return {
    actorUid: admin.uid,
    actorEmail: admin.email ?? '',
    actorName: admin.displayName ?? '',
    action: input.action,
    entityType: 'contract',
    entityId: input.entityId,
    before: input.before ?? null,
    after: input.after ?? null,
    message: input.message,
    createdAt: serverTimestamp(),
    source: 'admin-web',
  };
}

function notificationTypeForStatus(status: ContractStatus) {
  const map: Record<ContractStatus, string> = {
    draft: 'draftSaved',
    awaitingPayment: 'awaitingPayment',
    processing: 'processing',
    missingData: 'missingRequirement',
    authenticated: 'authenticated',
    rejected: 'rejected',
  };
  return map[status];
}

function notificationBodyForStatus(status: ContractStatus, note: string) {
  if (note) return note;
  if (status === 'awaitingPayment') return 'طلبك جاهز للدفع، إجمالي الرسوم 398 ريال.';
  if (status === 'processing') return 'طلبك قيد المعالجة لدى الفريق.';
  if (status === 'authenticated') return 'تم إصدار العقد النهائي ويمكنك تحميله من تفاصيل الطلب.';
  return statusLabelForStatus(status);
}

function timelineTitleForStatus(status: ContractStatus) {
  const map: Record<ContractStatus, string> = {
    draft: 'مسودة',
    awaitingPayment: 'بانتظار الدفع',
    processing: 'قيد المعالجة',
    missingData: 'يوجد نقص مطلوب',
    authenticated: 'تم إصدار العقد النهائي',
    rejected: 'تم رفض الطلب',
  };
  return map[status];
}

function statusLabelForStatus(status: ContractStatus) {
  const map: Record<ContractStatus, string> = {
    draft: 'مسودة',
    awaitingPayment: 'بانتظار الدفع',
    processing: 'قيد المعالجة',
    missingData: 'نواقص مطلوبة',
    authenticated: 'مكتمل',
    rejected: 'مرفوض',
  };
  return map[status];
}

function formatDateLabel(value: Date) {
  return `${value.getFullYear()}/${String(value.getMonth() + 1).padStart(2, '0')}/${String(value.getDate()).padStart(2, '0')}`;
}

function formatTimeLabel(value: Date) {
  return `${String(value.getHours()).padStart(2, '0')}:${String(value.getMinutes()).padStart(2, '0')}`;
}

function normalizeContract(input: Record<string, unknown>): Contract {
  return {
    ...input,
    status: normalizeStatus(input.status),
  } as Contract;
}

function normalizeStatus(value: unknown): ContractStatus {
  const raw = String(value || '');
  if (raw === 'underReview' || raw === 'readyForEjar' || raw === 'enteredInEjar' || raw === 'awaitingAuthentication') {
    return 'processing';
  }
  return CONTRACT_STATUSES.includes(raw as ContractStatus)
    ? raw as ContractStatus
    : 'processing';
}
