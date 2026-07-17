export type PaymentStatus = 'pending' | 'paid' | 'failed' | 'refunded' | 'cancelled';
export type PaymentMethod = 'mada' | 'applePay' | 'bankTransfer';

export interface Payment {
  id: string;
  contractId: string;
  userId: string;
  amount: number;
  currency: 'SAR';
  method: PaymentMethod;
  status: PaymentStatus;
  provider?: string;
  providerRef?: string;
  createdAt: unknown;
  paidAt?: unknown;
  updatedAt?: unknown;
  [key: string]: unknown;
}

export interface Invoice {
  id: string;
  contractId?: string;
  userId?: string;
  invoiceNumber?: string;
  amount?: number;
  currency?: 'SAR';
  status?: PaymentStatus;
  items?: Array<{ title: string; amount: number }>;
  createdAt?: unknown;
  updatedAt?: unknown;
  [key: string]: unknown;
}
