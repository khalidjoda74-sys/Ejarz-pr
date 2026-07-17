import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from './useAuth';
import { FullPageLoader } from '@/components/feedback/FullPageLoader';

export function AdminGate() {
  const { user, admin, loading, adminLoading } = useAuth();
  const location = useLocation();
  if (loading || adminLoading) return <FullPageLoader label="جاري التحقق من صلاحيات الدخول" />;
  if (!user) return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  if (!admin || !admin.active) return <Navigate to="/access-denied" replace />;
  return <Outlet />;
}
