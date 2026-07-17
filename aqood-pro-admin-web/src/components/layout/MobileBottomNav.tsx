import { useState } from 'react';
import { NavLink } from 'react-router-dom';
import { mobileNavItems, navItems } from './navItems';

export function MobileBottomNav() {
  const [open, setOpen] = useState(false);
  const directItems = mobileNavItems.filter((item) => item.to !== '__more__');
  return <>
    {open && <div className="mobile-more-backdrop" onClick={() => setOpen(false)} />}
    {open && <div className="mobile-more-panel">
      <div className="mobile-more-header">
        <strong>?? ????? ??????</strong>
        <button type="button" onClick={() => setOpen(false)}>?????</button>
      </div>
      <div className="mobile-more-grid">
        {navItems.map((item) => <NavLink key={item.to} to={item.to} onClick={() => setOpen(false)}>
          <span>{item.icon}</span>
          <span>{item.label}</span>
        </NavLink>)}
      </div>
    </div>}
    <nav className="mobile-bottom-nav">
      {directItems.map((item) => <NavLink key={item.to} to={item.to}>
        <span>{item.icon}</span>
        <span>{item.label}</span>
      </NavLink>)}
      <button type="button" className={open ? 'active' : ''} onClick={() => setOpen((value) => !value)}>
        <span>?</span>
        <span>??????</span>
      </button>
    </nav>
  </>;
}
