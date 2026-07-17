import { Permission } from '@/types/admin';
import { useAuth } from './useAuth';
import { hasPermission } from '@/lib/permissions';

export function usePermissions() {
  const { admin } = useAuth();
  return {
    admin,
    can: (permission: Permission | string) => hasPermission(admin, permission),
    isOwner: admin?.role === 'owner',
  };
}
