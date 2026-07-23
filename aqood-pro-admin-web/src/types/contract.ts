export type ContractStatus =
  | 'draft'
  | 'awaitingPayment'
  | 'processing'
  | 'missingData'
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
  id?: string;
  title: string;
  subtitle?: string;
  description?: string;
  status?: string;
  eventStatus?: ContractStatus;
  date?: unknown;
  time?: unknown;
  completed?: boolean;
  current?: boolean;
  createdAt?: unknown;
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
  title?: string;
  name?: string;
  fileName?: string;
  url?: string;
  downloadUrl?: string;
  path?: string;
  storagePath?: string;
  type?: string;
  createdAt?: unknown;
  uploadedAt?: unknown;
  uploadedBy?: string;
}

export type ContractRecordMap = Record<string, unknown>;

export interface ContractDraftData {
  type?: string;
  role?: string;
  urgent?: boolean;
  property?: ContractRecordMap;
  lessor?: ContractRecordMap;
  tenant?: ContractRecordMap;
  representative?: ContractRecordMap;
  duration?: ContractRecordMap;
  financial?: ContractRecordMap;
  services?: ContractRecordMap;
  terms?: ContractRecordMap;
  attachments?: ContractRecordMap[];
  installments?: ContractRecordMap[];
}

export interface MissingRequirement {
  id: string;
  title: string;
  description?: string;
  type?: string;
  issueCode?: string;
  fieldPath?: string;
  required?: boolean;
  resolved?: boolean;
}

export interface MissingRequirementResponse {
  id: string;
  uid?: string;
  userId?: string;
  contractId: string;
  missingRequirementId: string;
  missingRequirementTitle?: string;
  message?: string;
  fileName?: string;
  status?: 'pendingAdminReview' | 'accepted' | 'returned';
  reviewNote?: string;
  reviewedBy?: string;
  reviewedAt?: unknown;
  createdAt?: unknown;
  updatedAt?: unknown;
}

export interface Contract {
  id: string;
  userId?: string;
  uid?: string;
  requestNumber?: string;
  orderNumber?: string;
  contractType?: string;
  type?: string;
  role?: string;
  status: ContractStatus;
  customerName?: string;
  customerPhone?: string;
  customerEmail?: string;
  propertySummary?: string;
  propertyTitle?: string;
  propertyId?: string;
  lessorSummary?: string;
  tenantSummary?: string;
  draftData?: ContractDraftData;
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
  missingRequirements?: MissingRequirement[];
  timeline?: TimelineItem[];
  internalNotes?: InternalNote[];
  customerVisibleNote?: string;
  customerNote?: string;
  rejectionReason?: string;
  rejectedAt?: unknown;
  rejectedBy?: string;
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
  paymentStatus?: string;
  paymentId?: string;
  invoiceId?: string;
  invoiceNumber?: string;
  paymentMethod?: string;
  paymentProvider?: string;
  paymentProviderReference?: string;
  cardBrand?: string;
  cardLast4?: string;
  paidAt?: unknown;
  isDemoPayment?: boolean;
  city?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
  [key: string]: unknown;
}

export const CONTRACT_STATUSES: ContractStatus[] = [
  'draft',
  'awaitingPayment',
  'processing',
  'missingData',
  'authenticated',
  'rejected',
];

export const CONTRACT_STATUS_LABELS: Record<ContractStatus, string> = {
  draft: 'مسودة',
  awaitingPayment: 'بانتظار الدفع',
  processing: 'قيد المعالجة',
  missingData: 'نواقص مطلوبة',
  authenticated: 'مكتمل',
  rejected: 'مرفوض',
};
