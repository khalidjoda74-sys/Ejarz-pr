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
const { ensureWorkspaceDemoAttachments } = require('./demo_attachment_seed');

async function main() {
  const officeSnap = await db.collection('users')
    .where('isDemo', '==', true)
    .where('role', '==', 'office')
    .get();

  let officeCount = 0;
  let totalProperties = 0;
  let totalTenants = 0;
  let totalMaintenance = 0;
  let totalContracts = 0;

  for (const officeDoc of officeSnap.docs) {
    officeCount += 1;
    const officeUid = officeDoc.id;
    const officeStats = await ensureWorkspaceDemoAttachments(
      db.collection('users').doc(officeUid),
    );
    totalProperties += officeStats.properties;
    totalTenants += officeStats.tenants;
    totalMaintenance += officeStats.maintenance;
    totalContracts += officeStats.contracts;
    console.log(
      `demo attachments officeUid=${officeUid} properties=${officeStats.properties} tenants=${officeStats.tenants} maintenance=${officeStats.maintenance} contracts=${officeStats.contracts}`,
    );

    const clientSnap = await db.collection('users')
      .where('demoOfficeId', '==', officeUid)
      .get();

    for (const clientDoc of clientSnap.docs) {
      const clientStats = await ensureWorkspaceDemoAttachments(clientDoc.ref);
      totalProperties += clientStats.properties;
      totalTenants += clientStats.tenants;
      totalMaintenance += clientStats.maintenance;
      totalContracts += clientStats.contracts;
      console.log(
        `demo attachments clientUid=${clientDoc.id} officeUid=${officeUid} properties=${clientStats.properties} tenants=${clientStats.tenants} maintenance=${clientStats.maintenance} contracts=${clientStats.contracts}`,
      );
    }
  }

  console.log(
    `done offices=${officeCount} properties=${totalProperties} tenants=${totalTenants} maintenance=${totalMaintenance} contracts=${totalContracts}`,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
