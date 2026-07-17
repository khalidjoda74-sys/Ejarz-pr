import { useEffect, useState } from 'react';
import { PageHeader } from '@/components/layout/PageHeader';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Field, Input, Textarea } from '@/components/ui/Field';
import { Badge } from '@/components/ui/Badge';
import { ConfirmDialog } from '@/components/feedback/ConfirmDialog';
import { ErrorState } from '@/components/feedback/ErrorState';
import { FullPageLoader } from '@/components/feedback/FullPageLoader';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/components/feedback/Toast';
import { getAppContentConfig, updateAppContentConfig } from '@/services/contentService';
import { AppContentConfig, DEFAULT_LEGAL_LINKS } from '@/types/content';
import { getErrorMessage } from '@/lib/errors';

const sections: Array<{ title: string; fields: Array<keyof AppContentConfig> }> = [
  { title: 'الرئيسية والترحيب', fields: ['homeGreetingPrefix', 'homeWelcome', 'homeHeroTitle', 'homeHeroSubtitle', 'homeHeroButtonText'] },
  { title: 'الخدمات', fields: ['homeServicesTitle', 'homeServicesAction', 'serviceResidentialTitle', 'serviceResidentialSubtitle', 'serviceCommercialTitle', 'serviceCommercialSubtitle', 'serviceRenewalTitle', 'serviceRenewalSubtitle', 'serviceRenewalMessage', 'serviceHandoverTitle', 'serviceHandoverSubtitle', 'serviceHandoverMessage'] },
  { title: 'العقارات والعقود الفارغة', fields: ['homePropertiesTitle', 'homePropertiesAction', 'homeEmptyPropertiesTitle', 'homeEmptyPropertiesSubtitle', 'homeEmptyPropertiesAction', 'homeContractsTitle', 'homeContractsAction', 'homeEmptyContractsTitle', 'homeEmptyContractsSubtitle', 'homeEmptyContractsAction'] },
  { title: 'الدعم', fields: ['supportInfo'] },
];

const labels: Record<string, string> = {
  homeGreetingPrefix: 'بادئة الترحيب', homeWelcome: 'نص الترحيب', homeHeroTitle: 'عنوان الهيرو', homeHeroSubtitle: 'وصف الهيرو', homeHeroButtonText: 'نص زر الهيرو',
  homeServicesTitle: 'عنوان الخدمات', homeServicesAction: 'إجراء الخدمات', serviceResidentialTitle: 'عنوان السكني', serviceResidentialSubtitle: 'وصف السكني', serviceCommercialTitle: 'عنوان التجاري', serviceCommercialSubtitle: 'وصف التجاري', serviceRenewalTitle: 'عنوان التجديد', serviceRenewalSubtitle: 'وصف التجديد', serviceRenewalMessage: 'رسالة التجديد', serviceHandoverTitle: 'عنوان التسليم', serviceHandoverSubtitle: 'وصف التسليم', serviceHandoverMessage: 'رسالة التسليم',
  homePropertiesTitle: 'عنوان العقارات', homePropertiesAction: 'إجراء العقارات', homeEmptyPropertiesTitle: 'عنوان عدم وجود عقارات', homeEmptyPropertiesSubtitle: 'وصف عدم وجود عقارات', homeEmptyPropertiesAction: 'زر عدم وجود عقارات', homeContractsTitle: 'عنوان العقود', homeContractsAction: 'إجراء العقود', homeEmptyContractsTitle: 'عنوان عدم وجود عقود', homeEmptyContractsSubtitle: 'وصف عدم وجود عقود', homeEmptyContractsAction: 'زر عدم وجود عقود', supportInfo: 'معلومات الدعم',
};

export function ContentPage() {
  const { admin } = useAuth();
  const toast = useToast();
  const [original, setOriginal] = useState<AppContentConfig>({});
  const [form, setForm] = useState<AppContentConfig>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirmMaintenance, setConfirmMaintenance] = useState(false);

  async function load() { setLoading(true); setError(null); try { const config = await getAppContentConfig(); setOriginal(config); setForm(config); } catch (err) { setError(getErrorMessage(err)); } finally { setLoading(false); } }
  useEffect(() => { load(); }, []);

  function updateField(key: keyof AppContentConfig, value: unknown) { setForm((prev) => ({ ...prev, [key]: value })); }

  async function save() {
    if (!admin) return;
    setSaving(true);
    try {
      const patch: Partial<AppContentConfig> = {};
      Object.entries(form).forEach(([key, value]) => {
        if (JSON.stringify(value) !== JSON.stringify((original as Record<string, unknown>)[key])) (patch as Record<string, unknown>)[key] = value;
      });
      await updateAppContentConfig(admin, original, patch);
      toast.push('تم حفظ محتوى التطبيق', 'success');
      await load();
    } catch (err) { toast.push(getErrorMessage(err), 'error'); } finally { setSaving(false); }
  }

  if (loading) return <FullPageLoader label="جاري تحميل محتوى التطبيق" />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  return <div className="stack"><PageHeader title="إدارة محتوى التطبيق" subtitle="تحكم في النصوص والروابط ووضع الصيانة من appContent/config." actions={<><Button variant="soft" onClick={load}>تحديث</Button><Button variant="gold" onClick={save} disabled={saving}>{saving ? 'جاري الحفظ...' : 'حفظ التعديلات'}</Button></>} />
    <Card style={{ padding: 18 }}><div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'center', flexWrap: 'wrap' }}><div><h2 className="section-title">وضع الصيانة</h2><p className="page-subtitle">عند حفظ التفعيل سيعرض التطبيق شاشة صيانة ويمنع الاستخدام لغير الأدمن أو النسخة التجريبية.</p></div><Button variant={form.maintenanceMode ? 'danger' : 'soft'} onClick={() => setConfirmMaintenance(true)}>{form.maintenanceMode ? 'الصيانة مفعلة' : 'الصيانة غير مفعلة'}</Button></div></Card>
    <div className="grid-2"><div className="stack">{sections.map((section) => <Card style={{ padding: 18 }} key={section.title}><h2 className="section-title">{section.title}</h2><div className="stack">{section.fields.map((field) => <Field key={String(field)} label={labels[String(field)] ?? String(field)}>{String(field).toLowerCase().includes('subtitle') || String(field).toLowerCase().includes('message') || String(field).toLowerCase().includes('info') ? <Textarea value={String(form[field] ?? '')} onChange={(e) => updateField(field, e.target.value)} /> : <Input value={String(form[field] ?? '')} onChange={(e) => updateField(field, e.target.value)} />}</Field>)}</div></Card>)}</div><div className="stack"><Card style={{ padding: 18 }} goldLine><h2 className="section-title">روابط الشروط والسياسات</h2>{(['privacy', 'terms', 'refund', 'accountDeletion'] as const).map((key) => <Field key={key} label={key}><Input value={form.legalLinks?.[key] ?? DEFAULT_LEGAL_LINKS[key]} onChange={(e) => updateField('legalLinks', { ...(form.legalLinks ?? DEFAULT_LEGAL_LINKS), [key]: e.target.value })} /></Field>)}</Card><Card style={{ padding: 18 }}><h2 className="section-title">معاينة مختصرة</h2><Badge tone="gold">{form.homeGreetingPrefix || 'مرحبا'}</Badge><h3>{form.homeHeroTitle || 'عنوان الهيرو'}</h3><p className="page-subtitle">{form.homeHeroSubtitle || 'وصف الهيرو يظهر هنا'}</p><Button variant="gold">{form.homeHeroButtonText || 'ابدأ الآن'}</Button></Card></div></div>
    <ConfirmDialog open={confirmMaintenance} danger title="تغيير وضع الصيانة؟" description="سيتم تغيير قيمة maintenanceMode في النموذج، ثم اضغط حفظ التعديلات لتطبيقها فورًا على التطبيق." confirmLabel="تغيير" onCancel={() => setConfirmMaintenance(false)} onConfirm={() => { updateField('maintenanceMode', !form.maintenanceMode); setConfirmMaintenance(false); }} />
  </div>;
}
