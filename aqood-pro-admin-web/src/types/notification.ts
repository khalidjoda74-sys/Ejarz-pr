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
    pushStatus?: 'pending' | 'sending' | 'sent' | 'failed' | 'notConfigured' | 'skipped' | 'partial';
    attempts?: number;
    error?: string;
    lastAttemptAt?: unknown;
    nextAttemptAt?: unknown;
    lockedAt?: unknown;
  };
  createdAt: unknown;
  createdBy?: string;
  [key: string]: unknown;
}

export interface AdminNotification {
  id: string;
  eventKey: string;
  audience: 'admin';
  recipientUid: string;
  requiredPermission?: string;
  entityType?: string;
  entityId?: string;
  contractId?: string;
  title: string;
  body: string;
  type: string;
  priority: NotificationPriority;
  actionType?: string;
  actionPayload?: {
    contractId?: string;
    ticketId?: string;
    paymentId?: string;
    uid?: string;
    [key: string]: unknown;
  };
  read: boolean;
  readAt?: unknown;
  createdAt: unknown;
}
