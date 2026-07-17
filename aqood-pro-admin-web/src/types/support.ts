export type SupportTicketStatus = 'open' | 'pending' | 'resolved' | 'closed';

export interface SupportReply {
  id: string;
  message: string;
  createdAt: unknown;
  createdBy: string;
  createdByName?: string;
  visibility?: 'admin' | 'customer';
}

export interface SupportTicket {
  id: string;
  uid?: string;
  userId?: string;
  contractId?: string;
  subject: string;
  message?: string;
  status: SupportTicketStatus;
  priority?: 'normal' | 'high';
  replies?: SupportReply[];
  customerName?: string;
  customerPhone?: string;
  customerEmail?: string;
  createdAt: unknown;
  updatedAt?: unknown;
  [key: string]: unknown;
}
