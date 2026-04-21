const DEMO_CLIENT_PHONE = '0559263771';
const DEMO_EMERGENCY_NAME = 'جهة اتصال الطوارئ';
const DEMO_TENANT_NOTES = 'عميل تجريبي مضاف تلقائيًا لعرض بيانات المستأجر كاملة في نسخة الديمو.';
const DEMO_COMPANY_NOTES = 'عميل شركة تجريبي مضاف تلقائيًا لعرض البيانات الكاملة في نسخة الديمو.';
const DEMO_PROVIDER_NOTES = 'مزود خدمة تجريبي مضاف تلقائيًا لعرض البيانات الكاملة في نسخة الديمو.';
const CLIENT_TYPE_TENANT = 'tenant';
const CLIENT_TYPE_COMPANY = 'company';
const CLIENT_TYPE_SERVICE_PROVIDER = 'serviceProvider';

function normalizeType(value) {
  const raw = String(value || '').trim().toLowerCase();
  if (!raw) return CLIENT_TYPE_TENANT;
  if (raw === CLIENT_TYPE_COMPANY.toLowerCase() || raw === 'شركة') {
    return CLIENT_TYPE_COMPANY;
  }
  if (
    raw === CLIENT_TYPE_SERVICE_PROVIDER.toLowerCase() ||
    raw === 'service_provider' ||
    raw === 'service-provider' ||
    raw === 'مزود خدمة'
  ) {
    return CLIENT_TYPE_SERVICE_PROVIDER;
  }
  return CLIENT_TYPE_TENANT;
}

function defaultNotesForType(type) {
  switch (type) {
    case CLIENT_TYPE_COMPANY:
      return DEMO_COMPANY_NOTES;
    case CLIENT_TYPE_SERVICE_PROVIDER:
      return DEMO_PROVIDER_NOTES;
    default:
      return DEMO_TENANT_NOTES;
  }
}

async function ensureWorkspaceDemoTenantFields(userRef) {
  const snap = await userRef.collection('tenants').get();
  let updated = 0;
  const now = Date.now();

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const clientType = normalizeType(data.clientType);
    const patch = {};

    if (String(data.phone || '').trim() !== DEMO_CLIENT_PHONE) {
      patch.phone = DEMO_CLIENT_PHONE;
    }

    const currentNotes = String(data.notes || '').trim();
    const desiredNotes = defaultNotesForType(clientType);
    if (!currentNotes || currentNotes !== desiredNotes) {
      patch.notes = desiredNotes;
    }

    if (clientType === CLIENT_TYPE_TENANT) {
      if (!String(data.emergencyName || '').trim()) {
        patch.emergencyName = DEMO_EMERGENCY_NAME;
      }
      if (String(data.emergencyPhone || '').trim() !== DEMO_CLIENT_PHONE) {
        patch.emergencyPhone = DEMO_CLIENT_PHONE;
      }
    }

    if (clientType === CLIENT_TYPE_COMPANY) {
      if (String(data.companyRepresentativePhone || '').trim() !== DEMO_CLIENT_PHONE) {
        patch.companyRepresentativePhone = DEMO_CLIENT_PHONE;
      }
    }

    if (Object.keys(patch).length === 0) continue;

    await doc.ref.set({
      ...patch,
      updatedAt: now,
    }, { merge: true });
    updated += 1;
  }

  return updated;
}

module.exports = {
  DEMO_CLIENT_PHONE,
  DEMO_EMERGENCY_NAME,
  ensureWorkspaceDemoTenantFields,
};
