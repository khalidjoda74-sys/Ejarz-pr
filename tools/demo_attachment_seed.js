const PROPERTY_ATTACHMENT_URL = 'https://via.placeholder.com/1280x720.png?text=Darvoo+Demo+Property';
const TENANT_ATTACHMENT_URL = 'https://via.placeholder.com/1280x720.png?text=Darvoo+Demo+Tenant';
const SERVICE_ATTACHMENT_URL = 'https://via.placeholder.com/1280x720.png?text=Darvoo+Demo+Service';
const CONTRACT_ATTACHMENT_URL = 'https://via.placeholder.com/1280x720.png?text=Darvoo+Demo+Contract';
const PROPERTY_DOCUMENT_TYPE = 'صك الكتروني';

function normalizeStringList(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => (item == null ? '' : String(item).trim()))
    .filter((item) => item !== '');
}

function hasAnyAttachment(value) {
  return normalizeStringList(value).length > 0;
}

function stableDigitsFromString(value, length) {
  let hash = 0;
  const normalized = String(value || '');
  for (let i = 0; i < normalized.length; i += 1) {
    hash = (hash * 31 + normalized.charCodeAt(i)) % 1000000000000;
  }
  return String(hash).padStart(length, '0').slice(-length);
}

async function ensurePropertyAttachments(userRef) {
  const snap = await userRef.collection('properties').get();
  let updated = 0;
  const now = Date.now();

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const existingPaths = normalizeStringList(data.documentAttachmentPaths);
    const existingSingle = String(data.documentAttachmentPath || '').trim();
    const existingType = String(data.documentType || '').trim();
    const existingNumber = String(data.documentNumber || '').trim();
    const existingDate = data.documentDate;
    const patch = {};

    if (existingPaths.length === 0 && !existingSingle) {
      patch.documentAttachmentPath = PROPERTY_ATTACHMENT_URL;
      patch.documentAttachmentPaths = [PROPERTY_ATTACHMENT_URL];
    }
    if (!existingType) {
      patch.documentType = PROPERTY_DOCUMENT_TYPE;
    }
    if (!existingNumber) {
      patch.documentNumber = stableDigitsFromString(doc.id, 10);
    }
    if (existingDate == null) {
      patch.documentDate = Number.isFinite(data.createdAt)
        ? data.createdAt
        : now;
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

async function ensureTenantAttachments(userRef) {
  const snap = await userRef.collection('tenants').get();
  let updated = 0;
  const now = Date.now();

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (hasAnyAttachment(data.attachmentPaths)) continue;

    await doc.ref.set({
      attachmentPaths: [TENANT_ATTACHMENT_URL],
      updatedAt: now,
    }, { merge: true });
    updated += 1;
  }

  return updated;
}

async function ensureMaintenanceAttachments(userRef) {
  const snap = await userRef.collection('maintenance').get();
  let updated = 0;
  const now = Date.now();

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (hasAnyAttachment(data.attachmentPaths)) continue;

    await doc.ref.set({
      attachmentPaths: [SERVICE_ATTACHMENT_URL],
      updatedAt: now,
    }, { merge: true });
    updated += 1;
  }

  return updated;
}

async function ensureContractAttachments(userRef) {
  const snap = await userRef.collection('contracts').get();
  let updated = 0;
  const now = Date.now();

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (hasAnyAttachment(data.attachmentPaths)) continue;

    await doc.ref.set({
      attachmentPaths: [CONTRACT_ATTACHMENT_URL],
      updatedAt: now,
    }, { merge: true });
    updated += 1;
  }

  return updated;
}

async function ensureWorkspaceDemoAttachments(userRef) {
  const properties = await ensurePropertyAttachments(userRef);
  const tenants = await ensureTenantAttachments(userRef);
  const maintenance = await ensureMaintenanceAttachments(userRef);
  const contracts = await ensureContractAttachments(userRef);

  return { properties, tenants, maintenance, contracts };
}

module.exports = {
  PROPERTY_ATTACHMENT_URL,
  TENANT_ATTACHMENT_URL,
  SERVICE_ATTACHMENT_URL,
  CONTRACT_ATTACHMENT_URL,
  PROPERTY_DOCUMENT_TYPE,
  ensureWorkspaceDemoAttachments,
};
