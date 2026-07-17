import { AdminUser, Permission } from '@/types/admin';

const ROLE_PERMISSIONS: Record<string, Permission[]> = {
  owner: [
    'contracts.read', 'contracts.write', 'users.read', 'users.write', 'payments.read', 'payments.write',
    'content.write', 'support.read', 'support.write', 'notifications.read', 'notifications.write', 'reports.read', 'admins.manage', 'audit.read',
  ],
  manager: ['contracts.read', 'contracts.write', 'users.read', 'payments.read', 'content.write', 'support.read', 'support.write', 'notifications.read', 'notifications.write', 'reports.read', 'audit.read'],
  reviewer: ['contracts.read', 'contracts.write', 'users.read', 'notifications.read', 'notifications.write', 'audit.read'],
  support: ['contracts.read', 'users.read', 'support.read', 'support.write', 'notifications.read', 'notifications.write'],
  finance: ['contracts.read', 'users.read', 'payments.read', 'payments.write', 'reports.read', 'audit.read'],
};

export function hasPermission(admin: AdminUser | null | undefined, permission: Permission | string) {
  if (!admin || !admin.active) return false;
  if (admin.role === 'owner') return true;
  const explicit = admin.permissions ?? [];
  const rolePermissions = ROLE_PERMISSIONS[admin.role] ?? [];
  return explicit.includes(permission) || rolePermissions.includes(permission as Permission);
}

export function canManageAdmins(admin: AdminUser | null | undefined) {
  return hasPermission(admin, 'admins.manage');
}
