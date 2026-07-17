import { Outlet } from 'react-router-dom';
import { Sidebar } from './Sidebar';
import { TopBar } from './TopBar';
import { MobileBottomNav } from './MobileBottomNav';

export function AppShell() {
  return <div className="app-shell">
    <Sidebar />
    <main className="main-zone">
      <TopBar />
      <Outlet />
    </main>
    <MobileBottomNav />
  </div>;
}
