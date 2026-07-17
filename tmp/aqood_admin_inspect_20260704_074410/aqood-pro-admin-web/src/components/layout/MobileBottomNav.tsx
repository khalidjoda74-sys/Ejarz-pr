import { NavLink } from 'react-router-dom';
import { mobileNavItems } from './navItems';

export function MobileBottomNav() {
  return <nav className="mobile-bottom-nav">
    {mobileNavItems.map((item) => <NavLink key={item.to} to={item.to}>
      <span>{item.icon}</span>
      <span>{item.label}</span>
    </NavLink>)}
  </nav>;
}
