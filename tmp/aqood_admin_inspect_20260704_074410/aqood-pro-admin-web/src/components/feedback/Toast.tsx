import { createContext, useCallback, useContext, useMemo, useState } from 'react';

type ToastTone = 'success' | 'error' | 'info';
interface ToastItem { id: string; message: string; tone: ToastTone; }
interface ToastContextValue { push: (message: string, tone?: ToastTone) => void; }

const ToastContext = createContext<ToastContextValue | null>(null);

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);
  const push = useCallback((message: string, tone: ToastTone = 'info') => {
    const id = crypto.randomUUID();
    setItems((prev) => [...prev, { id, message, tone }]);
    window.setTimeout(() => setItems((prev) => prev.filter((item) => item.id !== id)), 4200);
  }, []);
  const value = useMemo(() => ({ push }), [push]);
  return <ToastContext.Provider value={value}>
    {children}
    <div className="toast-stack">
      {items.map((item) => <div key={item.id} className="toast">
        <span className={`badge badge-${item.tone === 'success' ? 'green' : item.tone === 'error' ? 'red' : 'navy'}`}>{item.tone === 'success' ? 'تم' : item.tone === 'error' ? 'خطأ' : 'تنبيه'}</span>
        <div style={{ marginTop: 8, fontWeight: 700 }}>{item.message}</div>
      </div>)}
    </div>
  </ToastContext.Provider>;
}

export function useToast() {
  const context = useContext(ToastContext);
  if (!context) throw new Error('useToast must be used within ToastProvider');
  return context;
}
