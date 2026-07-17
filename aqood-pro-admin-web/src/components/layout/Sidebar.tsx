import { NavLink } from 'react-router-dom';
import { navItems } from './navItems';
import { useAuth } from '@/hooks/useAuth';
import { roleLabel } from '@/lib/formatters';

export function Sidebar() {
  const { admin } = useAuth();
  return <aside className="sidebar">
    <div className="brand-card">
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <div className="brand-mark">عق</div>
        <div className="brand-copy">
          <div style={{ fontWeight: 850, fontSize: '1.08rem' }}>عقود برو</div>
          <div style={{ color: 'rgba(255,255,255,.58)', fontSize: '.8rem' }}>Command Center</div>
        </div>
      </div>
    </div>
    <div className="nav-section-title" style={{ margin: '22px 12px 10px', color: 'rgba(255,255,255,.42)', fontSize: '.78rem' }}>مركز العمليات</div>
    <nav style={{ display: 'grid', gap: 6 }}>
      {navItems.map((item) => <NavLink key={item.to} to={item.to} className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}>
        <span className="nav-icon">{item.icon}</span>
        <span className="nav-label">{item.label}</span>
      </NavLink>)}
    </nav>
    <div className="brand-card" style={{ marginTop: 18 }}>
      <div className="nav-label" style={{ fontWeight: 800 }}>{admin?.displayName || admin?.email || 'أدمن'}</div>
      <div className="nav-label" style={{ color: 'rgba(255,255,255,.58)', fontSize: '.8rem', marginTop: 4 }}>{roleLabel(admin?.role)}</div>
    </div>
  </aside>;
}
