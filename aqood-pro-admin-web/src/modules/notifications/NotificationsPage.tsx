import { ColumnDef } from '@tanstack/react-table';
import { useMemo } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { DataGrid } from '@/components/data/DataGrid';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';
import { ErrorState } from '@/components/feedback/ErrorState';
import { TableSkeleton } from '@/components/feedback/Skeletons';
import { useFirestoreQuery } from '@/hooks/useFirestoreQuery';
import {
  adminNotificationPath,
  listNotifications,
  markAdminNotificationRead,
  markAllAdminNotificationsRead,
} from '@/services/notificationService';
import { AppNotification } from '@/types/notification';
import { safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { useAdminNotifications } from '@/hooks/useAdminNotifications';

export function NotificationsPage() {
  const navigate = useNavigate();
  const { data, loading, error, refresh } = useFirestoreQuery(() => listNotifications(160), []);
  const {
    admin,
    items: adminNotifications,
    unreadCount,
    loading: adminLoading,
    error: adminError,
  } = useAdminNotifications();
  const columns = useMemo<ColumnDef<AppNotification>[]>(() => [
    { accessorKey: 'title', header: 'العنوان', cell: ({ row }) => <div><strong>{safeText(row.original.title)}</strong><div className="page-subtitle" style={{ margin: 0 }}>{safeText(row.original.body)}</div></div> },
    { accessorKey: 'uid', header: 'UID', cell: ({ row }) => safeText(row.original.uid || row.original.userId) },
    { accessorKey: 'contractId', header: 'العقد', cell: ({ row }) => safeText(row.original.contractId) },
    { accessorKey: 'priority', header: 'الأولوية', cell: ({ row }) => <Badge tone={row.original.priority === 'high' ? 'red' : 'gold'}>{row.original.priority === 'high' ? 'عالية' : 'عادية'}</Badge> },
    { accessorKey: 'delivery', header: 'Push', cell: ({ row }) => <Badge tone="gray">{safeText(row.original.delivery?.pushStatus)}</Badge> },
    { accessorKey: 'createdAt', header: 'التاريخ', cell: ({ row }) => formatDate(row.original.createdAt) },
  ], []);

  async function openAdminNotification(id: string) {
    const item = adminNotifications.find((notification) => notification.id === id);
    if (!item) return;
    if (!item.read) await markAdminNotificationRead(item.id);
    navigate(adminNotificationPath(item));
  }

  return <div className="stack">
    <PageHeader
      title="الإشعارات"
      subtitle="تنبيهات الإدارة اللحظية وسجل الإشعارات المرسلة للعملاء."
      actions={<>
        <Button variant="soft" onClick={refresh}>تحديث سجل العملاء</Button>
        <Link to="/notifications/new"><Button variant="gold">إشعار جديد</Button></Link>
      </>}
    />

    <section className="card" style={{ padding: 18 }}>
      <div className="section-heading-row">
        <div>
          <h2 className="section-title">تنبيهات الإدارة</h2>
          <p className="page-subtitle">تظهر فور وصول عقد أو استكمال أو تذكرة أو عملية مالية مهمة.</p>
        </div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <Badge tone={unreadCount ? 'red' : 'green'}>{unreadCount} غير مقروء</Badge>
          <Button
            variant="soft"
            disabled={!unreadCount || !admin?.uid}
            onClick={() => admin?.uid && void markAllAdminNotificationsRead(admin.uid)}
          >تعليم الكل كمقروء</Button>
        </div>
      </div>
      {adminLoading && <TableSkeleton />}
      {adminError && <ErrorState message={adminError} />}
      {!adminLoading && !adminError && <div className="admin-notification-page-list">
        {adminNotifications.map((item) => <button
          type="button"
          key={item.id}
          className={`admin-notification-page-item${item.read ? '' : ' unread'}`}
          onClick={() => void openAdminNotification(item.id)}
        >
          <span className="admin-notification-dot" />
          <span className="admin-notification-page-copy">
            <strong>{item.title}</strong>
            <span>{item.body}</span>
          </span>
          <span className="admin-notification-page-meta">
            <Badge tone={item.priority === 'high' ? 'red' : 'gray'}>{item.priority === 'high' ? 'عالية' : 'عادية'}</Badge>
            <small>{formatDate(item.createdAt)}</small>
          </span>
        </button>)}
        {!adminNotifications.length && <p className="page-subtitle">لا توجد تنبيهات إدارية حتى الآن.</p>}
      </div>}
    </section>

    <section className="stack">
      <div>
        <h2 className="section-title">سجل إشعارات العملاء</h2>
        <p className="page-subtitle">للمتابعة والتدقيق في حالة تسليم الإشعارات الداخلية وPush.</p>
      </div>
      {loading && <TableSkeleton />}
      {error && <ErrorState message={error} onRetry={refresh} />}
      {!loading && !error && <DataGrid
        data={data ?? []}
        columns={columns}
        mobileTitle={(row) => row.title}
        mobileSubtitle={(row) => safeText(row.body)}
        mobileMeta={(row) => <><Badge tone={row.priority === 'high' ? 'red' : 'gold'}>{row.priority === 'high' ? 'عالية' : 'عادية'}</Badge> <Badge tone="gray">{formatDate(row.createdAt)}</Badge></>}
      />}
    </section>
  </div>;
}
