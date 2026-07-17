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

export const router = createBrowserRouter([
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
          { path: '/contracts', element: <ContractsPage /> },
          { path: '/contracts/:contractId', element: <ContractDetailsPage /> },
          { path: '/users', element: <UsersPage /> },
          { path: '/users/:uid', element: <UserDetailsPage /> },
          { path: '/properties', element: <PropertiesPage /> },
          { path: '/properties/:propertyId', element: <PropertyDetailsPage /> },
          { path: '/payments', element: <PaymentsPage /> },
          { path: '/invoices', element: <InvoicesPage /> },
          { path: '/notifications', element: <NotificationsPage /> },
          { path: '/notifications/new', element: <NotificationNewPage /> },
          { path: '/support', element: <SupportPage /> },
          { path: '/support/:ticketId', element: <SupportDetailsPage /> },
          { path: '/content', element: <ContentPage /> },
          { path: '/admins', element: <AdminsPage /> },
          { path: '/admins/:uid', element: <AdminDetailsPage /> },
          { path: '/reports', element: <ReportsPage /> },
          { path: '/audit', element: <AuditPage /> },
          { path: '/settings', element: <SettingsPage /> },
        ],
      },
    ],
  },
  { path: '*', element: <Navigate to="/dashboard" replace /> },
]);
