export type AdminRole = 'owner' | 'manager' | 'reviewer' | 'support' | 'finance';

export interface AdminUser {
  uid: string;
  email?: string;
  displayName?: string;
  phone?: string;
  active: boolean;
  role: AdminRole;
  permissions?: string[];
  createdAt?: unknown;
  updatedAt?: unknown;
  lastLoginAt?: unknown;
}

export const ADMIN_ROLES: AdminRole[] = ['owner', 'manager', 'reviewer', 'support', 'finance'];

export const ADMIN_ROLE_LABELS: Record<AdminRole, string> = {
  owner: 'مالك النظام',
  manager: 'مدير عام',
  reviewer: 'مراجع عقود',
  support: 'دعم فني',
  finance: 'مالية',
};

export const ALL_PERMISSIONS = [
  'contracts.read',
  'contracts.write',
  'users.read',
  'users.write',
  'payments.read',
  'payments.write',
  'content.write',
  'support.read',
  'support.write',
  'notifications.read',
  'notifications.write',
  'reports.read',
  'admins.manage',
  'audit.read',
] as const;

export type Permission = (typeof ALL_PERMISSIONS)[number];
