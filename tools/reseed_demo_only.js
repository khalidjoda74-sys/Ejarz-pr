process.env.GOOGLE_CLOUD_PROJECT = 'darvoo';
process.env.GCLOUD_PROJECT = 'darvoo';
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'darvoo' });

const admin = require('C:\\Users\\khali\\Desktop\\web\\admin_panel\\functions\\node_modules\\firebase-admin');
const sa = require('C:\\Users\\khali\\Desktop\\web\\admin_panel\\functions\\serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    projectId: sa.project_id,
  });
}

const db = admin.firestore();
const mod = require('C:\\Users\\khali\\Desktop\\web\\admin_panel\\functions\\index.js');
const { buildDemoOfficeSeed, seedDemoOfficeData } = mod.__getDemoSeedHelpers();
const { ensureWorkspaceDemoAttachments } = require('./demo_attachment_seed');
const { ensureWorkspaceDemoTenantFields } = require('./demo_tenant_fields_seed');
const { buildDemoUnlimitedPackageSnapshot } = require('./demo_package_snapshot_seed');
const VALID_DEMO_LOGO_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY/j///9/AAn7A/0FQ0XKAAAAAElFTkSuQmCC';

async function deleteQueryDocs(query, batchSize = 450) {
  while (true) {
    const snap = await query.limit(batchSize).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    if (snap.size < batchSize) break;
  }
}

async function clearWorkspace(uid, { deleteOfficeRoot = false } = {}) {
  const userRef = db.collection('users').doc(uid);
  for (const name of ['properties', 'tenants', 'contracts', 'invoices', 'maintenance', 'session', 'notifications']) {
    await deleteQueryDocs(userRef.collection(name)).catch(() => {});
  }
  await db.collection('user_prefs').doc(uid).delete().catch(() => {});
  if (deleteOfficeRoot) {
    const officeRef = db.collection('offices').doc(uid);
    await deleteQueryDocs(officeRef.collection('clients')).catch(() => {});
  }
}

async function main() {
  const snap = await db.collection('users')
    .where('isDemo', '==', true)
    .where('role', '==', 'office')
    .get();

  console.log(`demo offices found=${snap.size}`);
  for (const doc of snap.docs) {
    const officeUid = doc.id;
    const officeName = String((doc.data() || {}).name || 'مكتب ديمو').trim() || 'مكتب ديمو';
    const seed = buildDemoOfficeSeed(officeUid, officeName);
    await clearWorkspace(officeUid, { deleteOfficeRoot: true });
    for (const officeClient of seed.officeClients) {
      await clearWorkspace(officeClient.uid, { deleteOfficeRoot: false });
    }
    await seedDemoOfficeData(officeUid, officeName);
    await db.collection('users').doc(officeUid).set({
      packageSnapshot: buildDemoUnlimitedPackageSnapshot(),
      packageName: 'تجريبي',
      office_profile: {
        logo_base64: VALID_DEMO_LOGO_BASE64,
      },
    }, { merge: true });
    await db.collection('offices').doc(officeUid).set({
      packageSnapshot: buildDemoUnlimitedPackageSnapshot(),
      packageName: 'تجريبي',
      office_profile: {
        logo_base64: VALID_DEMO_LOGO_BASE64,
      },
    }, { merge: true });
    const officeAttachmentStats = await ensureWorkspaceDemoAttachments(
      db.collection('users').doc(officeUid),
    );
    const officeTenantFieldsUpdated = await ensureWorkspaceDemoTenantFields(
      db.collection('users').doc(officeUid),
    );
    for (const officeClient of seed.officeClients) {
      const clientAttachmentStats = await ensureWorkspaceDemoAttachments(
        db.collection('users').doc(officeClient.uid),
      );
      const clientTenantFieldsUpdated = await ensureWorkspaceDemoTenantFields(
        db.collection('users').doc(officeClient.uid),
      );
      console.log(
        `demo attachments clientUid=${officeClient.uid} properties=${clientAttachmentStats.properties} tenants=${clientAttachmentStats.tenants} maintenance=${clientAttachmentStats.maintenance} contracts=${clientAttachmentStats.contracts} tenantFields=${clientTenantFieldsUpdated}`,
      );
    }
    console.log(
      `demo attachments officeUid=${officeUid} properties=${officeAttachmentStats.properties} tenants=${officeAttachmentStats.tenants} maintenance=${officeAttachmentStats.maintenance} contracts=${officeAttachmentStats.contracts} tenantFields=${officeTenantFieldsUpdated}`,
    );
    console.log(`reseeded officeUid=${officeUid}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
