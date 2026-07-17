export type AuditEntityType =
  | 'contract'
  | 'user'
  | 'property'
  | 'notification'
  | 'payment'
  | 'invoice'
  | 'supportTicket'
  | 'content'
  | 'admin';

export interface AuditLog {
  id: string;
  actorUid: string;
  actorEmail?: string;
  actorName?: string;
  action: string;
  entityType: AuditEntityType;
  entityId?: string;
  before?: unknown;
  after?: unknown;
  message?: string;
  createdAt: unknown;
  source: 'admin-web';
  [key: string]: unknown;
}
