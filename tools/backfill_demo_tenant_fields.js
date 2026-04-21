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
const { ensureWorkspaceDemoTenantFields } = require('./demo_tenant_fields_seed');

async function main() {
  const officeSnap = await db.collection('users')
    .where('isDemo', '==', true)
    .where('role', '==', 'office')
    .get();

  let officeCount = 0;
  let totalTenants = 0;

  for (const officeDoc of officeSnap.docs) {
    officeCount += 1;
    const officeUid = officeDoc.id;
    const officeUpdated = await ensureWorkspaceDemoTenantFields(officeDoc.ref);
    totalTenants += officeUpdated;
    console.log(`demo tenant fields officeUid=${officeUid} updated=${officeUpdated}`);

    const clientSnap = await db.collection('users')
      .where('demoOfficeId', '==', officeUid)
      .get();

    for (const clientDoc of clientSnap.docs) {
      const clientUpdated = await ensureWorkspaceDemoTenantFields(clientDoc.ref);
      totalTenants += clientUpdated;
      console.log(
        `demo tenant fields clientUid=${clientDoc.id} officeUid=${officeUid} updated=${clientUpdated}`,
      );
    }
  }

  console.log(`done offices=${officeCount} tenants=${totalTenants}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
