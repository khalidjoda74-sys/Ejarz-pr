import { useEffect, useMemo, useState } from 'react';
import { useAuth } from './useAuth';
import { AdminNotification } from '@/types/notification';
import { watchAdminNotifications } from '@/services/notificationService';

export function useAdminNotifications() {
  const { admin } = useAuth();
  const [items, setItems] = useState<AdminNotification[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!admin?.uid) {
      setItems([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    return watchAdminNotifications(
      admin.uid,
      (next) => {
        setItems(next);
        setLoading(false);
        setError(null);
      },
      (nextError) => {
        setError(nextError.message);
        setLoading(false);
      },
    );
  }, [admin?.uid]);

  const unreadCount = useMemo(() => items.filter((item) => !item.read).length, [items]);
  return { admin, items, unreadCount, loading, error };
}
