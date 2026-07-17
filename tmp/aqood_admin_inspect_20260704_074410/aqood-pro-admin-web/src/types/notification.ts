export type NotificationPriority = 'normal' | 'high';

export interface AppNotification {
  id: string;
  userId?: string;
  contractId?: string;
  title: string;
  body: string;
  priority: NotificationPriority;
  actionType?: 'contractDetails' | string;
  actionPayload?: {
    contractId?: string;
    [key: string]: unknown;
  };
  read?: boolean;
  delivery?: {
    pushStatus?: 'pending' | 'sent' | 'failed' | 'notConfigured';
  };
  createdAt: unknown;
  createdBy?: string;
  [key: string]: unknown;
}
