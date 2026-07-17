import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { Card } from '@/components/ui/Card';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { InfoItem } from '@/components/ui/InfoItem';
import { ErrorState } from '@/components/feedback/ErrorState';
import { FullPageLoader } from '@/components/feedback/FullPageLoader';
import { getProperty, listPropertyContracts } from '@/services/propertyService';
import { Property } from '@/types/property';
import { Contract } from '@/types/contract';
import { safeText } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { getErrorMessage } from '@/lib/errors';

const unitLabels: Record<string, string> = {
  number: 'رقم الوحدة',
  name: 'اسم الوحدة',
  type: 'نوع الوحدة',
  floor: 'الدور',
  area: 'المساحة',
  status: 'الحالة',
  roomsCount: 'غرف النوم',
  bathroomsCount: 'دورات المياه',
  hallsCount: 'الصالات',
  maidRoom: 'غرفة خادمة',
  kitchen: 'مطبخ',
  storage: 'مخزن',
  majlis: 'مجلس',
  furnishingStatus: 'التأثيث',
  privateParking: 'موقف خاص',
  electricityMeter: 'عداد الكهرباء',
  waterMeter: 'عداد المياه',
  gasMeter: 'عداد الغاز',
  acWindow: 'تكييف شباك',
  acSplit: 'تكييف سبليت',
  acCentral: 'تكييف مركزي',
  notes: 'ملاحظات',
};

function displayValue(value: unknown) {
  if (typeof value === 'boolean') return value ? 'نعم' : 'لا';
  return value;
}

export function PropertyDetailsPage() {
  const { propertyId = '' } = useParams();
  const [property, setProperty] = useState<Property | null>(null);
  const [contracts, setContracts] = useState<Contract[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  async function load() {
    setLoading(true); setError(null);
    try {
      const record = await getProperty(propertyId);
      setProperty(record);
      setContracts(await listPropertyContracts(propertyId).catch(() => []));
    } catch (err) { setError(getErrorMessage(err)); } finally { setLoading(false); }
  }
  useEffect(() => { load(); }, [propertyId]);
  if (loading) return <FullPageLoader label="جاري تحميل العقار" />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!property) return <ErrorState message="العقار غير موجود" onRetry={load} />;
  const units = property.units ?? [];
  const ownerUid = property.uid || property.userId;
  return <div className="stack">
    <PageHeader title="تفاصيل العقار" subtitle="عرض العقار والوحدات والعقود المرتبطة." actions={<Link to="/properties"><Button variant="soft">رجوع</Button></Link>} />
    <section className="detail-hero"><div><Badge tone="gold">{safeText(property.type, 'عقار')}</Badge><h1 className="page-title" style={{ marginTop: 12 }}>{safeText(property.title || property.ownerName || property.id)}</h1><p>{safeText(property.city)} · {safeText(property.district)} · {formatDate(property.createdAt)}</p></div><div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}><Badge tone="navy">{units.length} وحدات</Badge><Badge tone="green">{contracts.length} عقود مرتبطة</Badge></div></section>
    <div className="grid-2">
      <Card style={{ padding: 18 }}><h2 className="section-title">بيانات العقار</h2><div className="info-grid"><InfoItem label="المالك" value={property.ownerName} /><InfoItem label="UID العميل" value={ownerUid} /><InfoItem label="المدينة" value={property.city} /><InfoItem label="الحي" value={property.district} /><InfoItem label="الاستخدام" value={property.usage} /><InfoItem label="النوع" value={property.type} /><InfoItem label="عدد الأدوار" value={property.floors} /><InfoItem label="إجمالي الوحدات" value={property.totalUnits} /><InfoItem label="الحالة" value={property.status} /><InfoItem label="عقد الإنشاء" value={property.sourceContractId} /></div></Card>
      <Card style={{ padding: 18 }}><h2 className="section-title">العقود المرتبطة</h2><div className="stack">{contracts.map((contract) => <Link key={contract.id} to={`/contracts/${contract.id}`} className="card-solid" style={{ padding: 12 }}><strong>{contract.requestNumber || contract.orderNumber || contract.id}</strong><p className="page-subtitle" style={{ margin: '4px 0 0' }}>{safeText(contract.title || contract.propertyTitle || contract.propertySummary)}</p><div style={{ marginTop: 8 }}><StatusBadge status={contract.status} /></div></Link>)}{!contracts.length && <p className="page-subtitle">لا توجد عقود مرتبطة.</p>}</div></Card>
    </div>
    <Card style={{ padding: 18 }}><h2 className="section-title">الوحدات</h2><div className="grid-3">{units.map((unit, index) => <div className="card-solid" style={{ padding: 14 }} key={`${unit.number || unit.name || index}`}><Badge tone="gold">وحدة {safeText(unit.number || index + 1)}</Badge><div className="info-grid" style={{ marginTop: 12 }}>{Object.entries(unitLabels).map(([key, label]) => <InfoItem key={key} label={label} value={displayValue(unit[key])} />)}</div></div>)}{!units.length && <p className="page-subtitle">لا توجد وحدات محفوظة.</p>}</div></Card>
  </div>;
}
