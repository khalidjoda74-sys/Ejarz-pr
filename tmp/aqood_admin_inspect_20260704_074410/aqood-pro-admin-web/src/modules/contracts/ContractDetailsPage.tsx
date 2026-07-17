import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { Card, SolidCard } from '@/components/ui/Card';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select, Textarea } from '@/components/ui/Field';
import { InfoItem } from '@/components/ui/InfoItem';
import { ConfirmDialog } from '@/components/feedback/ConfirmDialog';
import { ErrorState } from '@/components/feedback/ErrorState';
import { FullPageLoader } from '@/components/feedback/FullPageLoader';
import { useToast } from '@/components/feedback/Toast';
import { useAuth } from '@/hooks/useAuth';
import { addInternalNote, addMissingItem, getContract, listContractFiles, markFinalPdfUploaded, updateContractStatus } from '@/services/contractService';
import { uploadFinalPdf } from '@/services/storageService';
import { Contract, CONTRACT_STATUSES, ContractFile, ContractStatus } from '@/types/contract';
import { formatCurrency, getRecordValue, safeText, statusLabel } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { getErrorMessage } from '@/lib/errors';

export function ContractDetailsPage() {
  const { contractId = '' } = useParams();
  const { admin } = useAuth();
  const toast = useToast();
  const [contract, setContract] = useState<Contract | null>(null);
  const [files, setFiles] = useState<ContractFile[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<ContractStatus>('underReview');
  const [customerNote, setCustomerNote] = useState('');
  const [missingTitle, setMissingTitle] = useState('');
  const [missingType, setMissingType] = useState<'field' | 'file' | 'clarification'>('field');
  const [missingDescription, setMissingDescription] = useState('');
  const [internalNote, setInternalNote] = useState('');
  const [confirmStatus, setConfirmStatus] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const item = await getContract(contractId);
      setContract(item);
      if (item) {
        setStatus(item.status);
        setCustomerNote(item.customerNote ?? '');
        setFiles(await listContractFiles(contractId).catch(() => []));
      }
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { load(); }, [contractId]);

  async function submitStatus() {
    if (!admin || !contract) return;
    try {
      await updateContractStatus(admin, contract, status, customerNote);
      toast.push('تم تحديث حالة العقد وإضافة السجل', 'success');
      setConfirmStatus(false);
      await load();
    } catch (err) {
      toast.push(getErrorMessage(err), 'error');
    }
  }

  async function submitMissing() {
    if (!admin || !contract || !missingTitle.trim()) return;
    try {
      await addMissingItem(admin, contract.id, { title: missingTitle, type: missingType, description: missingDescription });
      toast.push('تم إضافة النقص وتحويل العقد إلى ناقص بيانات', 'success');
      setMissingTitle(''); setMissingDescription(''); setMissingType('field');
      await load();
    } catch (err) {
      toast.push(getErrorMessage(err), 'error');
    }
  }

  async function submitInternalNote() {
    if (!admin || !contract || !internalNote.trim()) return;
    try {
      await addInternalNote(admin, contract.id, internalNote);
      toast.push('تم حفظ الملاحظة الداخلية', 'success');
      setInternalNote('');
      await load();
    } catch (err) {
      toast.push(getErrorMessage(err), 'error');
    }
  }

  async function handlePdf(file?: File | null) {
    if (!file || !admin || !contract) return;
    try {
      setUploadProgress(1);
      const uploaded = await uploadFinalPdf(contract.id, file, setUploadProgress);
      await markFinalPdfUploaded(admin, contract, uploaded.name, uploaded.url);
      toast.push('تم رفع PDF النهائي وتحويل العقد إلى مكتمل', 'success');
      setUploadProgress(0);
      await load();
    } catch (err) {
      setUploadProgress(0);
      toast.push(getErrorMessage(err), 'error');
    }
  }

  if (loading) return <FullPageLoader label="جاري تحميل ملف العقد" />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!contract) return <ErrorState message="العقد غير موجود" onRetry={load} />;

  return <div className="stack">
    <PageHeader title="ملف العقد" subtitle="صفحة معاملة كاملة تشمل البيانات والإجراءات والسجل." actions={<><Link to="/contracts"><Button variant="soft">رجوع</Button></Link><Button variant="soft" onClick={load}>تحديث</Button></>} />

    <section className="detail-hero">
      <div>
        <StatusBadge status={contract.status} />
        <h1 className="page-title" style={{ marginTop: 12 }}>{contract.orderNumber || contract.id}</h1>
        <p>{safeText(contract.customerName)} · {safeText(contract.customerPhone)} · {formatDate(contract.createdAt)}</p>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 14 }}>
          <Badge tone="gold">{safeText(contract.contractType, 'نوع غير محدد')}</Badge>
          <Badge tone="green">{formatCurrency(contract.totalPayable ?? contract.totalFees ?? 398)}</Badge>
          <Badge tone="navy">الأدمن: {safeText(contract.assignedAdminName)}</Badge>
        </div>
      </div>
      <div className="card-solid" style={{ padding: 14, minWidth: 250 }}>
        <Field label="تغيير الحالة"><Select value={status} onChange={(e) => setStatus(e.target.value as ContractStatus)}>{CONTRACT_STATUSES.map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}</Select></Field>
        <div style={{ height: 10 }} />
        <Field label="ملاحظة تظهر للعميل"><Textarea value={customerNote} onChange={(e) => setCustomerNote(e.target.value)} placeholder="اكتب ملاحظة مختصرة للعميل..." /></Field>
        <Button variant="gold" style={{ width: '100%', marginTop: 10 }} onClick={() => setConfirmStatus(true)}>حفظ الحالة</Button>
      </div>
    </section>

    <div className="grid-2">
      <div className="stack">
        <InfoSection title="بيانات العميل" items={[['الاسم', contract.customerName], ['الجوال', contract.customerPhone], ['البريد', contract.customerEmail], ['UID', contract.userId || contract.uid]]} />
        <RecordSection title="بيانات المؤجر" record={contract.landlord} />
        <RecordSection title="بيانات المستأجر" record={contract.tenant} />
        <RecordSection title="الممثل أو الوكيل" record={contract.representative} />
        <RecordSection title="الملكية" record={contract.ownership} />
        <RecordSection title="العقار والوحدة" record={{ ...(contract.property ?? {}), ...(contract.unit ?? {}) }} />
        <RecordSection title="المرافق والعدادات والتكييف والمواقف" record={{ utilities: contract.utilities, meters: contract.meters, airConditioning: contract.airConditioning, parking: contract.parking }} />
        <RecordSection title="البيانات المالية والدفعات" record={{ financial: contract.financial, payments: contract.payments, totalPayable: contract.totalPayable ?? 398, ejarPlatformFee: 299, serviceFee: 99 }} />
        <Card style={{ padding: 18 }}>
          <h2 className="section-title">الشروط الإضافية</h2>
          {contract.extraTerms?.length ? contract.extraTerms.map((term, index) => <p key={index} className="card-solid" style={{ padding: 12 }}>{term}</p>) : <p className="page-subtitle">لا توجد شروط إضافية.</p>}
        </Card>
      </div>

      <aside className="stack">
        <Card style={{ padding: 18 }} goldLine>
          <h2 className="section-title">رفع PDF النهائي</h2>
          <p className="page-subtitle">سيتم رفع الملف إلى Storage وتحويل الحالة إلى مكتمل.</p>
          <Input type="file" accept="application/pdf,.pdf" onChange={(e) => handlePdf(e.target.files?.[0])} />
          {uploadProgress > 0 && <div style={{ marginTop: 12 }}><div className="skeleton" style={{ height: 10, width: `${uploadProgress}%` }} /><p className="page-subtitle">{uploadProgress}%</p></div>}
          {contract.finalPdfUrl && <a className="badge badge-green" style={{ marginTop: 12 }} href={contract.finalPdfUrl} target="_blank" rel="noreferrer">فتح PDF النهائي</a>}
        </Card>

        <Card style={{ padding: 18 }}>
          <h2 className="section-title">النواقص</h2>
          <div className="stack">
            <Field label="عنوان النقص"><Input value={missingTitle} onChange={(e) => setMissingTitle(e.target.value)} /></Field>
            <Field label="نوع النقص"><Select value={missingType} onChange={(e) => setMissingType(e.target.value as 'field' | 'file' | 'clarification')}><option value="field">حقل</option><option value="file">ملف</option><option value="clarification">توضيح</option></Select></Field>
            <Field label="الوصف"><Textarea value={missingDescription} onChange={(e) => setMissingDescription(e.target.value)} /></Field>
            <Button variant="gold" onClick={submitMissing}>إضافة نقص</Button>
          </div>
          <div className="timeline" style={{ marginTop: 16 }}>
            {contract.missingItems?.map((item) => <div className="timeline-item" key={item.id}><Badge tone={item.status === 'open' ? 'red' : 'green'}>{item.status === 'open' ? 'مفتوح' : 'مغلق'}</Badge><strong style={{ display: 'block', marginTop: 8 }}>{item.title}</strong><p className="page-subtitle">{item.description}</p></div>)}
          </div>
        </Card>

        <Card style={{ padding: 18 }}>
          <h2 className="section-title">المرفقات</h2>
          <div className="stack">
            {files.map((file) => <a href={file.url} target="_blank" rel="noreferrer" key={file.id} className="card-solid" style={{ padding: 12 }}><strong>{safeText(file.fileName || file.name)}</strong><p className="page-subtitle" style={{ margin: 0 }}>{formatDate(file.uploadedAt)}</p></a>)}
            {!files.length && <p className="page-subtitle">لا توجد مرفقات في subcollection files.</p>}
          </div>
        </Card>

        <Card style={{ padding: 18 }}>
          <h2 className="section-title">ملاحظات داخلية</h2>
          <Textarea value={internalNote} onChange={(e) => setInternalNote(e.target.value)} placeholder="لا تظهر للعميل..." />
          <Button variant="soft" style={{ marginTop: 10 }} onClick={submitInternalNote}>حفظ ملاحظة</Button>
          <div className="timeline" style={{ marginTop: 16 }}>
            {contract.internalNotes?.map((note) => <div className="timeline-item" key={note.id}><strong>{note.createdByName}</strong><p>{note.note}</p><p className="page-subtitle">{formatDate(note.createdAt)}</p></div>)}
          </div>
        </Card>

        <Card style={{ padding: 18 }}>
          <h2 className="section-title">Timeline</h2>
          <div className="timeline">
            {contract.timeline?.map((item) => <div className="timeline-item" key={item.id}><strong>{item.title}</strong><p className="page-subtitle">{item.description}</p><p className="page-subtitle">{formatDate(item.createdAt)}</p></div>)}
            {!contract.timeline?.length && <p className="page-subtitle">لا يوجد timeline بعد.</p>}
          </div>
        </Card>
      </aside>
    </div>

    <ConfirmDialog open={confirmStatus} title="تأكيد تغيير حالة العقد" description="سيتم تحديث الحالة وكتابة auditLog وإنشاء إشعار للعميل إن وجد userId." confirmLabel="تأكيد التغيير" onCancel={() => setConfirmStatus(false)} onConfirm={submitStatus} />
  </div>;
}

function InfoSection({ title, items }: { title: string; items: Array<[string, unknown]> }) {
  return <Card style={{ padding: 18 }}><h2 className="section-title">{title}</h2><div className="info-grid">{items.map(([label, value]) => <InfoItem key={label} label={label} value={value} />)}</div></Card>;
}

function RecordSection({ title, record }: { title: string; record?: Record<string, unknown> }) {
  const entries = Object.entries(record ?? {}).filter(([, value]) => value !== undefined && value !== null && value !== '');
  return <Card style={{ padding: 18 }}><h2 className="section-title">{title}</h2>{entries.length ? <div className="info-grid">{entries.slice(0, 12).map(([key, value]) => <InfoItem key={key} label={key} value={typeof value === 'object' ? JSON.stringify(value) : value} />)}</div> : <p className="page-subtitle">غير متوفر.</p>}</Card>;
}
