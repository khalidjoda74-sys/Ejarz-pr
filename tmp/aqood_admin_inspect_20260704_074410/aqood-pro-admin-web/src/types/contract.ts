export type ContractStatus =
  | 'draft'
  | 'awaitingPayment'
  | 'underReview'
  | 'missingData'
  | 'readyForEjar'
  | 'enteredInEjar'
  | 'awaitingAuthentication'
  | 'authenticated'
  | 'rejected';

export type MissingItemType = 'field' | 'file' | 'clarification';
export type MissingItemStatus = 'open' | 'resolved';

export interface MissingItem {
  id: string;
  title: string;
  description?: string;
  type: MissingItemType;
  status: MissingItemStatus;
  createdAt: unknown;
  createdBy: string;
  resolvedAt?: unknown;
  resolvedBy?: string;
}

export interface TimelineItem {
  id: string;
  title: string;
  description?: string;
  status?: string;
  createdAt: unknown;
  createdBy?: string;
}

export interface InternalNote {
  id: string;
  note: string;
  createdAt: unknown;
  createdBy: string;
  createdByName?: string;
}

export interface ContractFile {
  id: string;
  name?: string;
  fileName?: string;
  url?: string;
  path?: string;
  type?: string;
  uploadedAt?: unknown;
  uploadedBy?: string;
}

export interface Contract {
  id: string;
  userId?: string;
  uid?: string;
  orderNumber?: string;
  contractType?: string;
  status: ContractStatus;
  customerName?: string;
  customerPhone?: string;
  customerEmail?: string;
  landlord?: Record<string, unknown>;
  tenant?: Record<string, unknown>;
  representative?: Record<string, unknown>;
  ownership?: Record<string, unknown>;
  property?: Record<string, unknown>;
  unit?: Record<string, unknown>;
  utilities?: Record<string, unknown>;
  meters?: Record<string, unknown>;
  airConditioning?: Record<string, unknown>;
  parking?: Record<string, unknown>;
  financial?: Record<string, unknown>;
  payments?: Record<string, unknown>;
  extraTerms?: string[];
  missingItems?: MissingItem[];
  timeline?: TimelineItem[];
  internalNotes?: InternalNote[];
  customerNote?: string;
  assignedAdminUid?: string;
  assignedAdminName?: string;
  finalPdfUrl?: string;
  finalPdfFileName?: string;
  finalPdfUploadedAt?: unknown;
  finalPdfUploadedBy?: string;
  totalFees?: number;
  ejarPlatformFee?: number;
  serviceFee?: number;
  totalPayable?: number;
  city?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
  [key: string]: unknown;
}

export const CONTRACT_STATUSES: ContractStatus[] = [
  'draft',
  'awaitingPayment',
  'underReview',
  'missingData',
  'readyForEjar',
  'enteredInEjar',
  'awaitingAuthentication',
  'authenticated',
  'rejected',
];

export const CONTRACT_STATUS_LABELS: Record<ContractStatus, string> = {
  draft: 'مسودة',
  awaitingPayment: 'بانتظار الدفع',
  underReview: 'قيد المراجعة',
  missingData: 'ناقص بيانات',
  readyForEjar: 'جاهز للإدخال',
  enteredInEjar: 'تم الإدخال في إيجار',
  awaitingAuthentication: 'بانتظار التوثيق',
  authenticated: 'مكتمل',
  rejected: 'مرفوض',
};
