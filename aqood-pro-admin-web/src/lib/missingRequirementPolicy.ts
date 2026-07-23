import type { MissingItemType } from '@/types/contract';

export type MissingReviewIssueCode =
  | 'unclear'
  | 'incorrect'
  | 'expired'
  | 'mismatch'
  | 'unverifiable'
  | 'additionalDocument'
  | 'clarification';

export interface MissingReviewTarget {
  key: string;
  title: string;
  type: MissingItemType;
  fieldPath: string;
}
export interface MissingReviewIssueOption {
  code: MissingReviewIssueCode;
  label: string;
}

export const MISSING_REVIEW_TARGETS: MissingReviewTarget[] = [
  { key: 'commercial-registration', title: 'السجل التجاري', type: 'file', fieldPath: 'draftData.attachments.commercial_registration' },
  { key: 'ownership-document', title: 'وثيقة الملكية', type: 'file', fieldPath: 'draftData.attachments.ownership' },
  { key: 'lessor-identity', title: 'هوية المؤجر', type: 'file', fieldPath: 'draftData.attachments.lessor_identity' },
  { key: 'tenant-identity', title: 'هوية المستأجر', type: 'file', fieldPath: 'draftData.attachments.tenant_identity' },
  { key: 'authorization', title: 'الوكالة أو التفويض', type: 'file', fieldPath: 'draftData.attachments.authorization' },
  { key: 'iban', title: 'وثيقة الآيبان', type: 'file', fieldPath: 'draftData.attachments.iban' },
  { key: 'electricity-meter', title: 'رقم عداد الكهرباء', type: 'field', fieldPath: 'draftData.property.electricityMeter' },
  { key: 'water-meter', title: 'رقم عداد المياه', type: 'field', fieldPath: 'draftData.property.waterMeter' },
  { key: 'gas-meter', title: 'رقم عداد الغاز', type: 'field', fieldPath: 'draftData.property.gasMeter' },
  { key: 'ownership-number', title: 'رقم وثيقة الملكية', type: 'field', fieldPath: 'draftData.property.ownershipDocumentNumber' },
  { key: 'commercial-registration-number', title: 'رقم السجل التجاري', type: 'field', fieldPath: 'draftData.tenant.commercialRegistration' },
  { key: 'national-address', title: 'العنوان الوطني', type: 'field', fieldPath: 'draftData.property.nationalAddress' },
  { key: 'other', title: 'متطلب آخر', type: 'clarification', fieldPath: '' },
];

const FILE_ISSUES: MissingReviewIssueOption[] = [
  { code: 'unclear', label: 'المستند غير واضح' },
  { code: 'incorrect', label: 'المستند غير صحيح' },
  { code: 'expired', label: 'المستند منتهي الصلاحية' },
  { code: 'mismatch', label: 'المستند غير مطابق للبيانات' },
];

const FIELD_ISSUES: MissingReviewIssueOption[] = [
  { code: 'incorrect', label: 'القيمة غير صحيحة' },
  { code: 'mismatch', label: 'القيمة غير مطابقة للبيانات' },
  { code: 'unverifiable', label: 'تعذر التحقق من القيمة' },
];

const OTHER_ISSUES: MissingReviewIssueOption[] = [
  { code: 'clarification', label: 'مطلوب توضيح إضافي' },
  { code: 'additionalDocument', label: 'مطلوب مستند إضافي' },
];

export function missingReviewIssuesFor(type: MissingItemType) {
  if (type === 'file') return FILE_ISSUES;
  if (type === 'field') return FIELD_ISSUES;
  return OTHER_ISSUES;
}

export function buildMissingReviewDescription(
  target: string,
  issueCode: MissingReviewIssueCode,
  note = '',
) {
  const title = target.trim();
  if (!title) throw new Error('حدد البيان أو المستند المطلوب مراجعته.');

  const base = (() => {
    switch (issueCode) {
      case 'unclear':
        return `${title} المرفق غير واضح. يرجى إعادة رفع نسخة واضحة وكاملة.`;
      case 'incorrect':
        return `${title} غير صحيح. يرجى مراجعته وإرسال البيانات أو المستند الصحيح.`;
      case 'expired':
        return `${title} المرفق منتهي الصلاحية. يرجى رفع نسخة سارية.`;
      case 'mismatch':
        return `${title} غير مطابق لبيانات الطلب. يرجى مراجعته وإرسال نسخة مطابقة.`;
      case 'unverifiable':
        return `تعذر التحقق من ${title}. يرجى مراجعته وإدخال القيمة الصحيحة.`;
      case 'additionalDocument':
        return `يلزم تقديم ${title} كمستند إضافي لاستكمال مراجعة الطلب.`;
      case 'clarification':
        return `نحتاج إلى توضيح إضافي بخصوص ${title} لاستكمال مراجعة الطلب.`;
    }
  })();

  const detail = note.trim();
  return detail ? `${base} ملاحظة الفريق: ${detail}` : base;
}

export function assertLogicalMissingRequirement(input: {
  title?: string;
  type?: string;
  issueCode?: string;
  description?: string;
}) {
  const title = String(input.title ?? '').trim();
  const description = String(input.description ?? '').trim();
  const issueCode = String(input.issueCode ?? '').trim() as MissingReviewIssueCode;
  const type = String(input.type ?? '').trim() as MissingItemType;
  if (!title) throw new Error('حدد البيان أو المستند محل المراجعة.');
  if (!['field', 'file', 'clarification'].includes(type)) throw new Error('نوع الملاحظة غير صالح.');
  if (!missingReviewIssuesFor(type).some((item) => item.code === issueCode)) {
    throw new Error('سبب الملاحظة لا يتوافق مع نوع البيان المحدد.');
  }
  if (!description) throw new Error('تعذر إنشاء وصف واضح للملاحظة.');
  if (issueCode !== 'additionalDocument' && /(?:غير\s+مرفق|لم\s+يتم\s+إرفاق|غير\s+مكتمل|لم\s+يكتمل)/i.test(description)) {
    throw new Error('لا يمكن وصف متطلب إجباري بأنه غير مرفق أو غير مكتمل بعد إرسال العقد. اختر سبب مراجعة دقيقًا.');
  }
}
