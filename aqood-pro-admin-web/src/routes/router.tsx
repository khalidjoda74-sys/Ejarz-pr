import type { ReactNode } from 'react';
import { Navigate, createBrowserRouter } from 'react-router-dom';
import { AdminGate } from '@/hooks/useAdminGate';
import { AppShell } from '@/components/layout/AppShell';
import { LoginPage } from '@/modules/auth/LoginPage';
import { AccessDeniedPage } from '@/modules/auth/AccessDeniedPage';
import { DashboardPage } from '@/modules/dashboard/DashboardPage';
import { ContractsPage } from '@/modules/contracts/ContractsPage';
import { ContractDetailsPage } from '@/modules/contracts/ContractDetailsPage';
import { UsersPage } from '@/modules/users/UsersPage';
import { UserDetailsPage } from '@/modules/users/UserDetailsPage';
import { PropertiesPage } from '@/modules/properties/PropertiesPage';
import { PropertyDetailsPage } from '@/modules/properties/PropertyDetailsPage';
import { PaymentsPage } from '@/modules/payments/PaymentsPage';
import { InvoicesPage } from '@/modules/payments/InvoicesPage';
import { NotificationsPage } from '@/modules/notifications/NotificationsPage';
import { NotificationNewPage } from '@/modules/notifications/NotificationNewPage';
import { SupportPage } from '@/modules/support/SupportPage';
import { SupportDetailsPage } from '@/modules/support/SupportDetailsPage';
import { ContentPage } from '@/modules/content/ContentPage';
import { AdminsPage } from '@/modules/admins/AdminsPage';
import { AdminDetailsPage } from '@/modules/admins/AdminDetailsPage';
import { ReportsPage } from '@/modules/reports/ReportsPage';
import { AuditPage } from '@/modules/audit/AuditPage';
import { SettingsPage } from '@/modules/settings/SettingsPage';
import { usePermissions } from '@/hooks/usePermissions';


function PermissionRoute({ permission, children }: { permission: string; children: ReactNode }) {
  const { can } = usePermissions();
  if (!can(permission)) return <AccessDeniedPage />;
  return <>{children}</>;
}

export const router = createBrowserRouter(
  [
    { path: '/login', element: <LoginPage /> },
    { path: '/access-denied', element: <AccessDeniedPage /> },
    {
      element: <AdminGate />,
      children: [
        {
          element: <AppShell />,
          children: [
            { index: true, element: <Navigate to="/dashboard" replace /> },
            { path: '/dashboard', element: <DashboardPage /> },
            { path: '/contracts', element: <PermissionRoute permission="contracts.read"><ContractsPage /></PermissionRoute> },
            { path: '/contracts/:contractId', element: <PermissionRoute permission="contracts.read"><ContractDetailsPage /></PermissionRoute> },
            { path: '/users', element: <PermissionRoute permission="users.read"><UsersPage /></PermissionRoute> },
            { path: '/users/:uid', element: <PermissionRoute permission="users.read"><UserDetailsPage /></PermissionRoute> },
            { path: '/properties', element: <PermissionRoute permission="contracts.read"><PropertiesPage /></PermissionRoute> },
            { path: '/properties/:propertyId', element: <PermissionRoute permission="contracts.read"><PropertyDetailsPage /></PermissionRoute> },
            { path: '/payments', element: <PermissionRoute permission="payments.read"><PaymentsPage /></PermissionRoute> },
            { path: '/invoices', element: <PermissionRoute permission="payments.read"><InvoicesPage /></PermissionRoute> },
            { path: '/notifications', element: <PermissionRoute permission="notifications.read"><NotificationsPage /></PermissionRoute> },
            { path: '/notifications/new', element: <PermissionRoute permission="notifications.write"><NotificationNewPage /></PermissionRoute> },
            { path: '/support', element: <PermissionRoute permission="support.read"><SupportPage /></PermissionRoute> },
            { path: '/support/:ticketId', element: <PermissionRoute permission="support.read"><SupportDetailsPage /></PermissionRoute> },
            { path: '/content', element: <PermissionRoute permission="content.write"><ContentPage /></PermissionRoute> },
            { path: '/admins', element: <PermissionRoute permission="admins.manage"><AdminsPage /></PermissionRoute> },
            { path: '/admins/:uid', element: <PermissionRoute permission="admins.manage"><AdminDetailsPage /></PermissionRoute> },
            { path: '/reports', element: <PermissionRoute permission="reports.read"><ReportsPage /></PermissionRoute> },
            { path: '/audit', element: <PermissionRoute permission="audit.read"><AuditPage /></PermissionRoute> },
            { path: '/settings', element: <SettingsPage /> },
          ],
        },
      ],
    },
    { path: '*', element: <Navigate to="/dashboard" replace /> },
  ],
  { basename: '/admin' },
);
