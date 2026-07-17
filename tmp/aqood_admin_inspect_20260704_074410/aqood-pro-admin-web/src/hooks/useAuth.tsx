import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import type { User } from 'firebase/auth';
import { AdminUser } from '@/types/admin';
import { getAdminUser, touchAdminLogin } from '@/services/adminService';
import { subscribeAuth } from '@/services/authService';

interface AuthContextValue {
  user: User | null;
  admin: AdminUser | null;
  loading: boolean;
  adminLoading: boolean;
  refreshAdmin: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [admin, setAdmin] = useState<AdminUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [adminLoading, setAdminLoading] = useState(false);

  async function loadAdmin(currentUser: User | null) {
    if (!currentUser) {
      setAdmin(null);
      return;
    }
    setAdminLoading(true);
    try {
      const record = await getAdminUser(currentUser.uid);
      if (record?.active) await touchAdminLogin(currentUser.uid).catch(() => undefined);
      setAdmin(record);
    } finally {
      setAdminLoading(false);
    }
  }

  useEffect(() => {
    const unsubscribe = subscribeAuth(async (nextUser) => {
      setUser(nextUser);
      setLoading(false);
      await loadAdmin(nextUser);
    });
    return unsubscribe;
  }, []);

  const value = useMemo<AuthContextValue>(() => ({
    user,
    admin,
    loading,
    adminLoading,
    refreshAdmin: () => loadAdmin(user),
  }), [user, admin, loading, adminLoading]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used inside AuthProvider');
  return context;
}
