import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { logout } from '@/services/authService';
import { isFirebaseConfigured, missingFirebaseKeys } from '@/lib/env';
import { useAuth } from '@/hooks/useAuth';
import { useDebounce } from '@/hooks/useDebounce';
import { GlobalSearchResult, globalSearch } from '@/services/globalSearchService';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';

const typeLabel: Record<GlobalSearchResult['type'], string> = {
  contract: 'عقد',
  user: 'مستخدم',
  property: 'عقار',
  support: 'دعم',
};

export function TopBar() {
  const { admin } = useAuth();
  const [term, setTerm] = useState('');
  const [results, setResults] = useState<GlobalSearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const debounced = useDebounce(term, 450);
  const navigate = useNavigate();
  const configured = isFirebaseConfigured();
  const missing = missingFirebaseKeys();

  useEffect(() => {
    let cancelled = false;
    async function run() {
      if (debounced.trim().length < 2) {
        setResults([]);
        return;
      }
      setLoading(true);
      const found = await globalSearch(debounced).catch(() => []);
      if (!cancelled) {
        setResults(found);
        setLoading(false);
      }
    }
    run();
    return () => { cancelled = true; };
  }, [debounced]);

  return <header className="topbar">
    <div className="search-box">
      <span className="search-symbol">⌕</span>
      <input value={term} onChange={(event) => setTerm(event.target.value)} placeholder="بحث عام: عقد، عميل، عقار، تذكرة..." />
      {(results.length > 0 || loading) && <div className="search-results">
        {loading && <div className="search-result-item"><span>جاري البحث...</span></div>}
        {!loading && results.map((result) => <button key={`${result.type}-${result.to}`} className="search-result-item" style={{ width: '100%', border: 0, cursor: 'pointer', textAlign: 'right' }} onClick={() => { setTerm(''); setResults([]); navigate(result.to); }}>
          <div>
            <strong>{result.title}</strong>
            <div className="page-subtitle" style={{ margin: 0 }}>{result.subtitle}</div>
          </div>
          <Badge tone="gold">{typeLabel[result.type]}</Badge>
        </button>)}
      </div>}
    </div>
    <div className="topbar-actions" style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
      <Badge tone={configured ? 'green' : 'red'}>{configured ? 'Firebase جاهز' : `env ناقص: ${missing.length}`}</Badge>
      <Link to="/notifications/new"><Button variant="gold">إشعار جديد</Button></Link>
      <span className="badge badge-navy">{admin?.displayName || admin?.email || 'أدمن'}</span>
      <Button variant="soft" onClick={() => logout()}>خروج</Button>
    </div>
  </header>;
}
