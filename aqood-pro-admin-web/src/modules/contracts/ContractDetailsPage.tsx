import { useEffect, useMemo, useState } from 'react';
import { contractAmount } from '@/lib/contractPricing';
import { Link, useParams } from 'react-router-dom';
import { PageHeader } from '@/components/layout/PageHeader';
import { Card } from '@/components/ui/Card';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select, Textarea } from '@/components/ui/Field';
import { InfoItem } from '@/components/ui/InfoItem';
import { ConfirmDialog } from '@/components/feedback/ConfirmDialog';
import { ErrorState } from '@/components/feedback/ErrorState';
import { FullPageLoader } from '@/components/feedback/FullPageLoader';
import { useToast } from '@/components/feedback/Toast';
import { useAuth } from '@/hooks/useAuth';
import { usePermissions } from '@/hooks/usePermissions';
import {
  addInternalNote,
  addMissingItem,
  getContract,
  listContractFiles,
  listMissingRequirementResponses,
  markFinalPdfUploaded,
  reviewMissingRequirementResponse,
  setMissingRequirementResolved,
  updateContractStatus,
} from '@/services/contractService';
import { uploadFinalPdf } from '@/services/storageService';
import {
  Contract,
  CONTRACT_STATUSES,
  ContractFile,
  ContractRecordMap,
  ContractStatus,
  MissingItem,
  MissingRequirement,
  MissingRequirementResponse,
} from '@/types/contract';
import { formatCurrency, safeText, statusLabel } from '@/lib/formatters';
import { formatDate } from '@/lib/dates';
import { getErrorMessage } from '@/lib/errors';
import {
  buildMissingReviewDescription,
  MISSING_REVIEW_TARGETS,
  missingReviewIssuesFor,
  MissingReviewIssueCode,
} from '@/lib/missingRequirementPolicy';

const ownershipKeys = ['ownershipDocumentType', 'ownershipDocumentNumber', 'ownershipDocumentDate'];

const propertyKeys = [
  'propertySource',
  'propertyUsage',
  'propertyType',
  'floorsCount',
  'unitsPerFloor',
  'totalUnits',
  'city',
  'district',
  'street',
  'buildingName',
  'buildingNumber',
  'additionalNumber',
  'postalCode',
  'notes',
];

const unitKeys = [
  'unitNumber',
  'unitName',
  'unitType',
  'floor',
  'area',
  'roomsCount',
  'bathroomsCount',
  'hallsCount',
  'maidRoom',
  'kitchen',
  'storage',
  'majlis',
  'furnishingStatus',
  'privateParking',
  'electricityMeter',
  'waterMeter',
  'gasMeter',
];

const acKeys = ['acWindow', 'acSplit', 'acCentral'];

const fieldLabels: Record<string, string> = {
  firstYearFee: 'رسوم السنة الأولى',
  additionalDurationFee: 'رسوم المدة الإضافية',
  includesEjarFees: 'شامل رسوم منصة إيجار',
  pricingVersion: 'نسخة التسعير',
  type: 'نوع العقد',
  role: 'دور مقدم الطلب',
  urgent: 'طلب عاجل',
  kind: 'نوع الطرف',
  fullName: 'الاسم',
  idType: 'نوع الهوية',
  idNumber: 'رقم الهوية',
  birthDate: 'تاريخ الميلاد',
  mobile: 'رقم الجوال',
  email: 'البريد الإلكتروني',
  city: 'المدينة',
  district: 'الحي',
  nationalAddress: 'العنوان الوطني',
  mobileRegisteredInAbsher: 'الجوال مسجل في أبشر',
  commercialRegistration: 'رقم السجل التجاري',
  unifiedNumber: 'الرقم الموحد',
  authorizedPersonName: 'اسم المفوض',
  authorizedPersonId: 'هوية المفوض',
  iban: 'الآيبان',
  bankName: 'اسم البنك',
  accountOwner: 'صاحب الحساب',
  enabled: 'مفعل',
  represents: 'يمثل',
  authorizationNumber: 'رقم التفويض',
  authorizationDate: 'تاريخ التفويض',
  issuer: 'جهة الإصدار',
  expiryDate: 'تاريخ الانتهاء',
  propertySource: 'مصدر العقار',
  ownershipDocumentType: 'نوع إثبات الملكية',
  ownershipDocumentNumber: 'رقم الوثيقة',
  ownershipDocumentDate: 'تاريخ الوثيقة',
  propertyUsage: 'استخدام العقار',
  propertyType: 'نوع العقار الرئيسي',
  floorsCount: 'عدد الأدوار',
  unitsPerFloor: 'عدد الوحدات في كل دور',
  totalUnits: 'إجمالي الوحدات',
  street: 'الشارع',
  buildingName: 'اسم المبنى',
  buildingNumber: 'رقم المبنى',
  additionalNumber: 'الرقم الإضافي',
  postalCode: 'الرمز البريدي',
  unitNumber: 'رقم الوحدة',
  unitName: 'اسم الوحدة',
  unitType: 'نوع الوحدة',
  floor: 'رقم الدور',
  area: 'مساحة الوحدة',
  roomsCount: 'غرف النوم',
  bathroomsCount: 'دورات المياه',
  hallsCount: 'الصالات',
  maidRoom: 'غرفة خادمة',
  kitchen: 'مطبخ',
  storage: 'مخزن',
  majlis: 'مجلس',
  furnishingStatus: 'حالة التأثيث',
  privateParking: 'موقف خاص',
  electricityMeter: 'رقم عداد الكهرباء',
  waterMeter: 'رقم عداد المياه',
  gasMeter: 'رقم عداد الغاز',
  acWindow: 'تكييف شباك',
  acSplit: 'تكييف سبليت',
  acCentral: 'تكييف مركزي',
  notes: 'ملاحظات',
  startDate: 'تاريخ البداية',
  endDate: 'تاريخ النهاية',
  years: 'سنوات',
  months: 'أشهر',
  days: 'أيام',
  rentValue: 'مبلغ الإيجار',
  rentPeriod: 'دورة الإيجار',
  hasSecurityDeposit: 'يوجد ضمان',
  securityDeposit: 'قيمة الضمان',
  paymentFrequency: 'دورة السداد',
  paymentCount: 'عدد الدفعات',
  paymentChannel: 'قناة الدفع',
  officialFeePayer: 'دافع رسوم إيجار',
  serviceFeePayer: 'دافع عمولة الخدمة',
  ejarPlatformFee: 'رسوم منصة إيجار',
  serviceFee: 'عمولة عقود برو',
  totalPayable: 'الإجمالي المستحق',
  paymentStatus: 'حالة الدفع',
  paymentId: 'Payment ID',
  invoiceId: 'Invoice ID',
  invoiceNumber: 'رقم الفاتورة',
  paymentMethod: 'طريقة الدفع',
  paymentProvider: 'مزود الدفع',
  paymentProviderReference: 'رقم العملية',
  cardBrand: 'نوع البطاقة',
  cardLast4: 'آخر 4 أرقام',
  paidAt: 'تاريخ الدفع',
  isDemoPayment: 'عملية تجريبية',
  electricity: 'الكهرباء',
  water: 'المياه',
  gas: 'الغاز',
  otherServices: 'خدمات أخرى',
  calculationMethod: 'طريقة الاحتساب',
  fixedAmount: 'المبلغ المقطوع',
  currentReading: 'القراءة الحالية',
  allowSublease: 'التأجير من الباطن',
  autoRenewal: 'التجديد التلقائي',
  specialTerms: 'الشروط الإضافية',
  keyName: 'المفتاح',
  title: 'العنوان',
  required: 'مطلوب',
  uploaded: 'مرفوع',
  fileName: 'اسم الملف',
  sizeLabel: 'حجم الملف',
  index: 'رقم الدفعة',
  amount: 'المبلغ',
  dueDate: 'تاريخ الاستحقاق',
  note: 'ملاحظة',
  fieldPath: 'مسار الحقل',
  resolved: 'تم الحل',
  status: 'الحالة',
};

const valueLabels: Record<string, string> = {
  residential: 'عقد سكني',
  commercial: 'عقد تجاري',
  lessor: 'مؤجر',
  tenant: 'مستأجر',
  authorized: 'وكيل / وسيط',
  individual: 'فرد',
  company: 'منشأة / شركة',
};

const ADMIN_STATUS_OPTIONS = CONTRACT_STATUSES.filter((item) => item !== 'draft');

export function ContractDetailsPage() {
  const { contractId = '' } = useParams();
  const { admin } = useAuth();
  const { can } = usePermissions();
  const canWrite = can('contracts.write');
  const toast = useToast();
  const [contract, setContract] = useState<Contract | null>(null);
  const [files, setFiles] = useState<ContractFile[]>([]);
  const [missingResponses, setMissingResponses] = useState<MissingRequirementResponse[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<ContractStatus>('processing');
  const [customerNote, setCustomerNote] = useState('');
  const [missingTargetKey, setMissingTargetKey] = useState('commercial-registration');
  const [missingIssueCode, setMissingIssueCode] = useState<MissingReviewIssueCode>('unclear');
  const [customMissingTitle, setCustomMissingTitle] = useState('');
  const [missingReviewNote, setMissingReviewNote] = useState('');
  const [internalNote, setInternalNote] = useState('');
  const [confirmStatus, setConfirmStatus] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [responseNotes, setResponseNotes] = useState<Record<string, string>>({});
  const [reviewingResponseId, setReviewingResponseId] = useState('');

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const item = await getContract(contractId);
      setContract(item);
      if (item) {
        setStatus(item.status === 'draft' ? 'awaitingPayment' : item.status);
        setCustomerNote(String(
          item.status === 'rejected'
            ? item.rejectionReason ?? item.customerVisibleNote ?? item.customerNote ?? ''
            : item.customerVisibleNote ?? item.customerNote ?? '',
        ));
        setFiles(await listContractFiles(contractId).catch(() => []));
        setMissingResponses(await listMissingRequirementResponses(contractId).catch(() => []));
      }
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, [contractId]);

  const view = useMemo(() => (contract ? buildContractView(contract) : null), [contract]);
  const isRejected = contract?.status === 'rejected';
  const missingTarget = useMemo(
    () => MISSING_REVIEW_TARGETS.find((item) => item.key === missingTargetKey) ?? MISSING_REVIEW_TARGETS[0],
    [missingTargetKey],
  );
  const missingIssueOptions = useMemo(() => missingReviewIssuesFor(missingTarget.type), [missingTarget.type]);
  const missingTitle = missingTarget.key === 'other' ? customMissingTitle.trim() : missingTarget.title;
  const missingDescription = useMemo(() => {
    if (!missingTitle || !missingIssueOptions.some((item) => item.code === missingIssueCode)) return '';
    return buildMissingReviewDescription(missingTitle, missingIssueCode, missingReviewNote);
  }, [missingIssueCode, missingIssueOptions, missingReviewNote, missingTitle]);

  useEffect(() => {
    if (!missingIssueOptions.some((item) => item.code === missingIssueCode)) {
      setMissingIssueCode(missingIssueOptions[0].code);
    }
  }, [missingIssueCode, missingIssueOptions]);

  async function submitStatus() {
    if (!admin || !contract || !canWrite) return;
    if (contract.status === 'rejected') {
      toast.push('الطلب مرفوض نهائيًا ولا يمكن تغيير حالته.', 'error');
      return;
    }
    if (status === 'rejected' && !customerNote.trim()) {
      toast.push('يجب كتابة سبب واضح لرفض الطلب.', 'error');
      return;
    }
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
    if (!admin || !contract || !canWrite || !missingTitle || !missingDescription) return;
    try {
      await addMissingItem(admin, contract, {
        title: missingTitle,
        type: missingTarget.type,
        issueCode: missingIssueCode,
        description: missingDescription,
        fieldPath: missingTarget.fieldPath,
      });
      toast.push('تم إرسال ملاحظة المراجعة للعميل وتحويل العقد إلى ناقص بيانات', 'success');
      setCustomMissingTitle('');
      setMissingReviewNote('');
      await load();
    } catch (err) {
      toast.push(getErrorMessage(err), 'error');
    }
  }

  async function submitInternalNote() {
    if (!admin || !contract || !canWrite || !internalNote.trim()) return;
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
    if (!file || !admin || !contract || !canWrite) return;
    try {
      setUploadProgress(1);
      const uploaded = await uploadFinalPdf(contract.id, file, setUploadProgress);
      await markFinalPdfUploaded(admin, contract, uploaded.name, uploaded.url, uploaded.path);
      toast.push('تم رفع PDF النهائي وتحويل العقد إلى مكتمل', 'success');
      setUploadProgress(0);
      await load();
    } catch (err) {
      setUploadProgress(0);
      toast.push(getErrorMessage(err), 'error');
    }
  }


  async function resolveMissing(requirementId: string) {
    if (!admin || !contract || !canWrite) return;
    try {
      await setMissingRequirementResolved(admin, contract, requirementId, true);
      toast.push('تم اعتماد متطلب المراجعة', 'success');
      await load();
    } catch (err) {
      toast.push(getErrorMessage(err), 'error');
    }
  }

  async function reviewResponse(response: MissingRequirementResponse, decision: 'accepted' | 'returned') {
    if (!admin || !contract || !canWrite) return;
    const note = String(responseNotes[response.id] ?? '').trim();
    if (decision === 'returned' && !note) {
      toast.push('اكتب سبب إعادة الاستكمال للعميل.', 'error');
      return;
    }
    try {
      setReviewingResponseId(response.id);
      await reviewMissingRequirementResponse(admin, contract, response, decision, note);
      toast.push(decision === 'accepted' ? 'تم اعتماد استكمال العميل.' : 'تمت إعادة الاستكمال للعميل مع السبب.', 'success');
      setResponseNotes((current) => ({ ...current, [response.id]: '' }));
      await load();
    } catch (err) {
      toast.push(getErrorMessage(err), 'error');
    } finally {
      setReviewingResponseId('');
    }
  }

  if (loading) return <FullPageLoader label="جاري تحميل ملف العقد" />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!contract || !view) return <ErrorState message="العقد غير موجود" onRetry={load} />;

  return <div className="stack">
    <PageHeader title="ملف العقد" subtitle="كل بيانات الطلب كما أدخلها العميل داخل التطبيق، مع fallback للحقول القديمة." actions={<><Link to="/contracts"><Button variant="soft">رجوع</Button></Link><Button variant="soft" onClick={load}>تحديث</Button></>} />

    <section className="detail-hero">
      <div>
        <StatusBadge status={contract.status} />
        <h1 className="page-title" style={{ marginTop: 12 }}>{view.requestNumber}</h1>
        <p>{safeText(contract.customerName)} · {safeText(contract.customerPhone)} · {formatDate(contract.createdAt)}</p>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 14 }}>
          <Badge tone="gold">{view.contractType}</Badge>
          <Badge tone="green">{formatCurrency(view.totalPayable)}</Badge>
          {view.paymentStatus === 'paid' && <Badge tone="green">مدفوع</Badge>}
          {Boolean(contract.isDemo) && <Badge tone="gold">Demo Data</Badge>}
          {contract.isDemoPayment && <Badge tone="gold">Demo Payment</Badge>}
          <Badge tone="navy">الأدمن: {safeText(contract.assignedAdminName)}</Badge>
        </div>
      </div>
      <div className="card-solid" style={{ padding: 14, minWidth: 250 }}>
        {isRejected ? <>
          <Badge tone="red">رفض نهائي</Badge>
          <h3 className="section-title" style={{ marginTop: 10 }}>سبب الرفض</h3>
          <p className="page-subtitle">{safeText(contract.rejectionReason || contract.customerVisibleNote, 'لم يُحفظ سبب الرفض في هذا السجل القديم.')}</p>
          <p className="page-subtitle">لا يمكن تغيير الحالة أو إضافة نواقص أو رفع عقد نهائي.</p>
        </> : <>
          <Field label="تغيير الحالة"><Select value={status} disabled={!canWrite} onChange={(e) => setStatus(e.target.value as ContractStatus)}>{ADMIN_STATUS_OPTIONS.filter((item) => item !== 'authenticated' && !(item === 'rejected' && (contract.status === 'draft' || contract.status === 'authenticated'))).map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}</Select></Field>
          <div style={{ height: 10 }} />
          <Field label={status === 'rejected' ? 'سبب الرفض (إلزامي)' : 'ملاحظة تظهر للعميل'}><Textarea value={customerNote} disabled={!canWrite} onChange={(e) => setCustomerNote(e.target.value)} placeholder={status === 'rejected' ? 'اكتب سببًا واضحًا يظهر للعميل...' : 'اكتب ملاحظة مختصرة للعميل...'} /></Field>
          <Button variant={status === 'rejected' ? 'danger' : 'gold'} style={{ width: '100%', marginTop: 10 }} disabled={!canWrite || (status === 'rejected' && !customerNote.trim())} onClick={() => setConfirmStatus(true)}>حفظ الحالة</Button>
        </>}
      </div>
    </section>

    <div className="grid-2">
      <div className="stack">
        <InfoSection title="بيانات العميل والطلب" items={[
          ['رقم الطلب', view.requestNumber],
          ['معرف العقد', contract.id],
          ['الاسم', contract.customerName],
          ['الجوال', contract.customerPhone],
          ['البريد', contract.customerEmail],
          ['UID', contract.uid || contract.userId],
          ['نوع العقد', view.contractType],
          ['دور مقدم الطلب', view.role],
          ...(isRejected ? [['سبب الرفض', contract.rejectionReason || contract.customerVisibleNote] as [string, unknown]] : []),
        ]} />
        <RecordSection title="الدفع والفاتورة" record={view.payment} />
        <RecordSection title="بيانات المؤجر" record={view.lessor} />
        <RecordSection title="بيانات المستأجر" record={view.tenant} />
        <RecordSection title="الممثل أو الوكيل" record={view.representative} />
        <RecordSection title="بيانات الملكية" record={view.ownership} />
        <RecordSection title="بيانات العقار الرئيسية" record={view.property} />
        <RecordSection title="بيانات الوحدة" record={view.unit} />
        <RecordSection title="التكييف" record={view.airConditioning} />
        <RecordSection title="مدة العقد" record={view.duration} />
        <RecordSection title="البيانات المالية" record={view.financial} />
        <RecordSection title="الخدمات والعدادات" record={view.services} />
        <RecordSection title="الشروط" record={view.terms} />
        <ListRecordSection title="جدول الدفعات" rows={view.installments} emptyText="لا يوجد جدول دفعات محفوظ." />
        <ListRecordSection title="المرفقات المدخلة من التطبيق" rows={view.attachments} emptyText="لا توجد مرفقات محفوظة في draftData." />
      </div>

      <aside className="stack">
        {!isRejected && <Card style={{ padding: 18 }} goldLine>
          <h2 className="section-title">رفع PDF النهائي</h2>
          <p className="page-subtitle">سيتم رفع الملف إلى Storage وتحويل الحالة إلى مكتمل.</p>
          <Input type="file" accept="application/pdf,.pdf" disabled={!canWrite} onChange={(e) => handlePdf(e.target.files?.[0])} />
          {uploadProgress > 0 && <div style={{ marginTop: 12 }}><div className="skeleton" style={{ height: 10, width: `${uploadProgress}%` }} /><p className="page-subtitle">{uploadProgress}%</p></div>}
          {contract.finalPdfUrl && <a className="badge badge-green" style={{ marginTop: 12 }} href={contract.finalPdfUrl} target="_blank" rel="noreferrer">فتح PDF النهائي</a>}
        </Card>}

        <Card style={{ padding: 18 }}>
          <h2 className="section-title">متطلبات المراجعة</h2>
          <p className="page-subtitle">المتطلبات الإجبارية تُفحص قبل إرسال العقد. اختر هنا مشكلة جودة أو صحة أو مطابقة، وليس غياب حقل إجباري.</p>
          {!isRejected && <div className="stack">
            <Field label="البيان أو المستند محل المراجعة">
              <Select value={missingTargetKey} onChange={(event) => setMissingTargetKey(event.target.value)}>
                {MISSING_REVIEW_TARGETS.map((item) => <option value={item.key} key={item.key}>{item.title}</option>)}
              </Select>
            </Field>
            {missingTarget.key === 'other' && <Field label="اسم المتطلب الإضافي"><Input value={customMissingTitle} onChange={(event) => setCustomMissingTitle(event.target.value)} placeholder="مثال: تفويض محدث" /></Field>}
            <Field label="سبب المراجعة">
              <Select value={missingIssueCode} onChange={(event) => setMissingIssueCode(event.target.value as MissingReviewIssueCode)}>
                {missingIssueOptions.map((item) => <option value={item.code} key={item.code}>{item.label}</option>)}
              </Select>
            </Field>
            <Field label="ملاحظة إضافية اختيارية"><Textarea value={missingReviewNote} onChange={(event) => setMissingReviewNote(event.target.value)} placeholder="أضف تفصيلًا مفيدًا للعميل دون تكرار النص الأساسي" /></Field>
            {missingDescription && <div className="card-solid" style={{ padding: 12 }}><strong>النص الذي سيظهر للعميل</strong><p className="page-subtitle" style={{ margin: '6px 0 0' }}>{missingDescription}</p></div>}
            <Button variant="gold" disabled={!canWrite || !missingTitle || !missingDescription} onClick={submitMissing}>إرسال ملاحظة المراجعة</Button>
          </div>}
          <div className="timeline" style={{ marginTop: 16 }}>
            {view.missingRequirements.map((item) => <MissingEntry item={item} key={item.id || item.title} canWrite={canWrite && !isRejected} onResolve={resolveMissing} />)}
            {!view.missingRequirements.length && <p className="page-subtitle">لا توجد متطلبات مراجعة مفتوحة.</p>}
          </div>
          <div className="stack" style={{ marginTop: 14 }}>
            <h3 className="section-title">الاستكمالات الواردة</h3>
            {missingResponses.map((response) => <div className="card-solid" style={{ padding: 12 }} key={response.id}>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, alignItems: 'center' }}>
                <strong>{safeText(response.missingRequirementTitle || response.missingRequirementId)}</strong>
                <Badge tone={response.status === 'accepted' ? 'green' : response.status === 'returned' ? 'red' : 'gold'}>
                  {response.status === 'accepted' ? 'معتمد' : response.status === 'returned' ? 'معاد للعميل' : 'بانتظار المراجعة'}
                </Badge>
              </div>
              <p className="page-subtitle" style={{ margin: '6px 0' }}>{safeText(response.message, '')}</p>
              {response.fileName && <Badge tone="blue">{response.fileName}</Badge>}
              <p className="page-subtitle" style={{ margin: '6px 0 0' }}>{formatDate(response.createdAt)}</p>
              {(!response.status || response.status === 'pendingAdminReview') && canWrite && !isRejected && <div className="stack" style={{ marginTop: 10 }}>
                <Field label="سبب الإعادة (مطلوب عند الإعادة)">
                  <Textarea
                    value={responseNotes[response.id] ?? ''}
                    onChange={(event) => setResponseNotes((current) => ({ ...current, [response.id]: event.target.value }))}
                    placeholder="اكتب للعميل التعديل المطلوب بوضوح"
                  />
                </Field>
                <div style={{ display: 'flex', gap: 8 }}>
                  <Button disabled={reviewingResponseId === response.id} onClick={() => void reviewResponse(response, 'accepted')}>اعتماد الاستكمال</Button>
                  <Button variant="danger" disabled={reviewingResponseId === response.id} onClick={() => void reviewResponse(response, 'returned')}>إعادة للعميل</Button>
                </div>
              </div>}
            </div>)}
            {!missingResponses.length && <p className="page-subtitle">لا توجد استكمالات واردة حتى الآن.</p>}
          </div>
        </Card>

        <Card style={{ padding: 18 }}>
          <h2 className="section-title">ملفات العقد النهائية</h2>
          <div className="stack">
            {files.map((file) => <a href={file.url ?? file.downloadUrl as string | undefined} target="_blank" rel="noreferrer" key={file.id} className="card-solid" style={{ padding: 12 }}><strong>{safeText(file.fileName || file.name || file.title)}</strong><p className="page-subtitle" style={{ margin: 0 }}>{formatDate(file.uploadedAt ?? file.createdAt)}</p></a>)}
            {!files.length && <p className="page-subtitle">لا توجد ملفات نهائية في subcollection files.</p>}
          </div>
        </Card>

        <Card style={{ padding: 18 }}>
          <h2 className="section-title">ملاحظات داخلية</h2>
          {!isRejected && <><Textarea value={internalNote} onChange={(e) => setInternalNote(e.target.value)} placeholder="لا تظهر للعميل..." />
          <Button variant="soft" style={{ marginTop: 10 }} disabled={!canWrite} onClick={submitInternalNote}>حفظ ملاحظة</Button></>}
          <div className="timeline" style={{ marginTop: 16 }}>
            {contract.internalNotes?.map((note) => <div className="timeline-item" key={note.id}><strong>{note.createdByName}</strong><p>{note.note}</p><p className="page-subtitle">{formatDate(note.createdAt)}</p></div>)}
          </div>
        </Card>

        <Card style={{ padding: 18 }}>
          <h2 className="section-title">سجل الحالة</h2>
          <div className="timeline">
            {view.timeline.map((item, index) => <div className={`timeline-item ${(item.eventStatus ?? item.status) === 'rejected' ? 'timeline-item-rejected' : ''}`} key={item.id || `${item.title}-${index}`}><strong>{safeText(item.title)}</strong><p className="page-subtitle">{safeText(item.description ?? item.subtitle, '')}</p><p className="page-subtitle">{formatTimelineDate(item)}</p></div>)}
            {!view.timeline.length && <p className="page-subtitle">لا يوجد سجل حالة بعد.</p>}
          </div>
        </Card>
      </aside>
    </div>

    <ConfirmDialog open={confirmStatus} title={status === 'rejected' ? 'رفض الطلب نهائيًا؟' : 'تأكيد تغيير حالة العقد'} description={status === 'rejected' ? 'سيصبح الطلب مرفوضًا نهائيًا، ولن يمكن تعديله أو إعادته إلى المعالجة.' : 'سيتم تحديث الحالة وكتابة سجل التدقيق، وسيُرسل إشعار الخادم للعميل.'} confirmLabel={status === 'rejected' ? 'رفض الطلب' : 'تأكيد التغيير'} onCancel={() => setConfirmStatus(false)} onConfirm={submitStatus} />
  </div>;
}

function InfoSection({ title, items }: { title: string; items: Array<[string, unknown]> }) {
  return <Card style={{ padding: 18 }}><h2 className="section-title">{title}</h2><div className="info-grid">{items.map(([label, value]) => <InfoItem key={label} label={label} value={formatValue(value)} />)}</div></Card>;
}

function RecordSection({ title, record }: { title: string; record?: ContractRecordMap }) {
  const entries = entriesOf(record);
  return <Card style={{ padding: 18 }}>
    <h2 className="section-title">{title}</h2>
    {entries.length ? <div className="info-grid">{entries.map(([key, value]) => <RecordInfoItem key={key} fieldKey={key} value={value} />)}</div> : <p className="page-subtitle">غير متوفر.</p>}
  </Card>;
}

function ListRecordSection({ title, rows, emptyText }: { title: string; rows: ContractRecordMap[]; emptyText: string }) {
  return <Card style={{ padding: 18 }}>
    <h2 className="section-title">{title}</h2>
    <div className="stack">
      {rows.map((row, index) => <div className="card-solid" style={{ padding: 12 }} key={String(row.id ?? row.keyName ?? row.index ?? index)}>
        <strong>{safeText(row.title ?? row.fileName ?? row.note ?? row.index ?? `عنصر ${index + 1}`)}</strong>
        <div className="info-grid" style={{ marginTop: 10 }}>{entriesOf(row).map(([key, value]) => <RecordInfoItem key={key} fieldKey={key} value={value} />)}</div>
      </div>)}
      {!rows.length && <p className="page-subtitle">{emptyText}</p>}
    </div>
  </Card>;
}

function RecordInfoItem({ fieldKey, value }: { fieldKey: string; value: unknown }) {
  return <div className="info-item">
    <span>{fieldLabels[fieldKey] ?? fieldKey}</span>
    <strong>{formatValue(value, fieldKey)}</strong>
  </div>;
}

function MissingEntry({
  item,
  canWrite,
  onResolve,
}: {
  item: MissingRequirement | MissingItem;
  canWrite: boolean;
  onResolve: (id: string) => void;
}) {
  const resolved = Boolean((item as MissingRequirement).resolved) || (item as MissingItem).status === 'resolved';
  const id = String(item.id || '');
  return <div className="timeline-item">
    <Badge tone={resolved ? 'green' : 'red'}>{resolved ? 'تم الحل' : 'مفتوح'}</Badge>
    <strong style={{ display: 'block', marginTop: 8 }}>{item.title}</strong>
    <p className="page-subtitle">{safeText(item.description, '')}</p>
    {'fieldPath' in item && item.fieldPath && <p className="page-subtitle">المسار: {item.fieldPath}</p>}
    {!resolved && id && <Button variant="soft" disabled={!canWrite} onClick={() => onResolve(id)}>تعليم كمحلول</Button>}
  </div>;
}

function buildContractView(contract: Contract) {
  const draft = contract.draftData ?? {};
  const draftProperty = asRecord(draft.property);
  const draftFinancial = asRecord(draft.financial);
  const draftServices = asRecord(draft.services);
  const draftTerms = asRecord(draft.terms);

  const type = draft.type ?? contract.type ?? contract.contractType;
  const role = draft.role ?? contract.role;
  const totalPayable = contractAmount(contract);

  return {
    requestNumber: safeText(contract.requestNumber ?? contract.orderNumber ?? contract.id),
    contractType: formatValue(type, 'type'),
    role: formatValue(role, 'role'),
    totalPayable,
    paymentStatus: contract.paymentStatus,
    payment: cleanRecord({
      paymentStatus: contract.paymentStatus,
      paymentId: contract.paymentId,
      invoiceId: contract.invoiceId,
      invoiceNumber: contract.invoiceNumber,
      paymentMethod: formatPaymentMethod(contract.paymentMethod),
      paymentProvider: contract.paymentProvider === 'demo' ? 'Demo Payment' : contract.paymentProvider,
      paymentProviderReference: contract.paymentProviderReference,
      cardBrand: contract.cardBrand,
      cardLast4: contract.cardLast4,
      paidAt: contract.paidAt,
      isDemoPayment: contract.isDemoPayment,
      totalFees: contract.totalFees,
      ejarPlatformFee: contract.ejarPlatformFee,
      serviceFee: contract.serviceFee,
      firstYearFee: draftFinancial?.firstYearFee,
      additionalDurationFee: draftFinancial?.additionalDurationFee,
      includesEjarFees: draftFinancial?.includesEjarFees,
      totalPayable,
    }),
    lessor: mergeRecords(asRecord(contract.landlord), asRecord(draft.lessor), {
      fullName: contract.lessorSummary,
    }),
    tenant: mergeRecords(asRecord(contract.tenant), asRecord(draft.tenant), {
      fullName: contract.tenantSummary,
    }),
    representative: mergeRecords(asRecord(contract.representative), asRecord(draft.representative)),
    ownership: mergeRecords(asRecord(contract.ownership), pickRecord(draftProperty, ownershipKeys)),
    property: mergeRecords(asRecord(contract.property), pickRecord(draftProperty, propertyKeys), {
      propertyTitle: contract.propertyTitle,
      propertySummary: contract.propertySummary,
      city: contract.city,
    }),
    unit: mergeRecords(asRecord(contract.unit), pickRecord(draftProperty, unitKeys)),
    airConditioning: mergeRecords(asRecord(contract.airConditioning), pickRecord(draftProperty, acKeys)),
    duration: mergeRecords(undefined, asRecord(draft.duration)),
    financial: mergeRecords(asRecord(contract.financial), draftFinancial, {
      totalFees: contract.totalFees,
      ejarPlatformFee: draftFinancial?.ejarPlatformFee ?? contract.ejarPlatformFee,
      serviceFee: draftFinancial?.serviceFee ?? contract.serviceFee,
      totalPayable,
    }),
    services: mergeRecords(
      {
        utilities: contract.utilities,
        meters: contract.meters,
        parking: contract.parking,
      },
      draftServices,
    ),
    terms: mergeRecords(undefined, draftTerms, {
      extraTerms: contract.extraTerms,
    }),
    attachments: arrayOfRecords(draft.attachments),
    installments: arrayOfRecords(draft.installments),
    missingRequirements: [...(contract.missingRequirements ?? []), ...(contract.missingItems ?? [])],
    timeline: contract.timeline ?? [],
  };
}

function asRecord(value: unknown): ContractRecordMap | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  return value as ContractRecordMap;
}

function mergeRecords(...records: Array<ContractRecordMap | undefined>): ContractRecordMap {
  return cleanRecord(Object.assign({}, ...records.filter(Boolean)));
}

function pickRecord(record: ContractRecordMap | undefined, keys: string[]): ContractRecordMap | undefined {
  if (!record) return undefined;
  return cleanRecord(Object.fromEntries(keys.map((key) => [key, record[key]])));
}

function arrayOfRecords(value: unknown): ContractRecordMap[] {
  return Array.isArray(value) ? value.map(asRecord).filter(Boolean) as ContractRecordMap[] : [];
}

function cleanRecord(record: ContractRecordMap): ContractRecordMap {
  return Object.fromEntries(Object.entries(record).filter(([, value]) => hasValue(value)));
}

function entriesOf(record?: ContractRecordMap) {
  return Object.entries(cleanRecord(record ?? {}));
}

function hasValue(value: unknown) {
  if (value === undefined || value === null || value === '') return false;
  if (Array.isArray(value)) return value.length > 0;
  if (typeof value === 'object') return Object.keys(value as Record<string, unknown>).length > 0;
  return true;
}

function formatValue(value: unknown, fieldKey?: string): string {
  if (value === undefined || value === null || value === '') return 'غير متوفر';
  if (typeof value === 'boolean') return value ? 'نعم' : 'لا';
  if (typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map((item) => formatValue(item)).join('، ');
  if (typeof value === 'object') {
    const entries = entriesOf(value as ContractRecordMap);
    if (!entries.length) return 'غير متوفر';
    return entries.map(([key, nestedValue]) => `${fieldLabels[key] ?? key}: ${formatValue(nestedValue, key)}`).join(' | ');
  }
  const raw = String(value);
  if (fieldKey === 'type' || fieldKey === 'role' || fieldKey === 'kind') return valueLabels[raw] ?? raw;
  return valueLabels[raw] ?? raw;
}

function formatPaymentMethod(value?: unknown) {
  const raw = typeof value === 'string' ? value : '';
  if (raw === 'mada') return 'مدى';
  if (raw === 'visaMastercard') return 'Visa / Mastercard';
  if (raw === 'applePay') return 'Apple Pay - Demo';
  if (raw === 'stcPay') return 'STC Pay - Demo';
  if (raw === 'bankTransfer') return 'تحويل بنكي';
  return raw;
}

function formatTimelineDate(item: { createdAt?: unknown; date?: unknown; time?: unknown }) {
  const parts = [item.date, item.time].filter(Boolean).map(String);
  if (parts.length) return parts.join(' - ');
  return formatDate(item.createdAt);
}
