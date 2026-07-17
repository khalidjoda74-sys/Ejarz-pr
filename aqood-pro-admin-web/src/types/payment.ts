export type PaymentStatus = 'pending' | 'paid' | 'failed' | 'refunded' | 'cancelled';
export type PaymentMethod = 'notSelected' | 'mada' | 'visaMastercard' | 'applePay' | 'stcPay' | 'bankTransfer';

export interface Payment {
  id: string;
  uid: string;
  contractId: string;
  userId?: string;
  amount: number;
  currency: 'SAR';
  ejarPlatformFee?: number;
  serviceFee?: number;
  method: PaymentMethod;
  status: PaymentStatus;
  provider?: string;
  providerReference?: string;
  providerRef?: string;
  cardBrand?: string;
  cardLast4?: string;
  failureReason?: string;
  isDemo?: boolean;
  createdAt: unknown;
  paidAt?: unknown;
  updatedAt?: unknown;
  [key: string]: unknown;
}

export interface Invoice {
  id: string;
  uid?: string;
  contractId?: string;
  userId?: string;
  invoiceNumber?: string;
  amount?: number;
  currency?: 'SAR';
  status?: PaymentStatus;
  paymentId?: string;
  pdfUrl?: string;
  isDemo?: boolean;
  items?: Array<{ title: string; amount: number }>;
  createdAt?: unknown;
  updatedAt?: unknown;
  [key: string]: unknown;
}
