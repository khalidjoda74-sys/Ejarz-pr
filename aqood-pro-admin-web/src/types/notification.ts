export type NotificationPriority = 'low' | 'normal' | 'high';

export interface NotificationChannels {
  inApp?: boolean;
  push?: boolean;
}

export interface AppNotification {
  id: string;
  uid?: string;
  userId?: string;
  contractId?: string;
  title: string;
  body: string;
  type?: string;
  priority: NotificationPriority;
  actionType?: 'contractDetails' | string;
  actionPayload?: {
    contractId?: string;
    ticketId?: string;
    [key: string]: unknown;
  };
  channels?: NotificationChannels;
  read?: boolean;
  readAt?: unknown;
  sentAt?: unknown;
  delivery?: {
    pushStatus?: 'pending' | 'sent' | 'failed' | 'notConfigured' | 'skipped' | 'partial';
    error?: string;
  };
  createdAt: unknown;
  createdBy?: string;
  [key: string]: unknown;
}
