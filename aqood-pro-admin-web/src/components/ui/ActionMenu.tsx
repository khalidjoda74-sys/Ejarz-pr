import { useState } from 'react';
import { Button } from './Button';

export interface ActionItem {
  label: string;
  onClick: () => void;
  danger?: boolean;
  disabled?: boolean;
}

export function ActionMenu({ actions }: { actions: ActionItem[] }) {
  const [open, setOpen] = useState(false);
  return <div style={{ position: 'relative', display: 'inline-block' }}>
    <Button type="button" variant="soft" onClick={() => setOpen((v) => !v)}>إجراءات</Button>
    {open && <div className="card-solid" style={{ position: 'absolute', top: 'calc(100% + 8px)', left: 0, minWidth: 190, padding: 8, zIndex: 30 }}>
      {actions.map((action) => <button
        key={action.label}
        type="button"
        disabled={action.disabled}
        onClick={() => { setOpen(false); action.onClick(); }}
        style={{ width: '100%', textAlign: 'right', padding: '10px 12px', border: 0, background: 'transparent', color: action.danger ? 'var(--danger)' : 'var(--navy-950)', cursor: 'pointer', borderRadius: 12 }}
      >{action.label}</button>)}
    </div>}
  </div>;
}
