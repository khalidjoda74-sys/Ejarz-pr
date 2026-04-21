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
const { buildDemoUnlimitedPackageSnapshot } = require('./demo_package_snapshot_seed');

async function main() {
  const packageSnapshot = buildDemoUnlimitedPackageSnapshot();
  const officeSnap = await db.collection('users')
    .where('isDemo', '==', true)
    .where('role', '==', 'office')
    .get();

  let updated = 0;

  for (const doc of officeSnap.docs) {
    const patch = {
      packageSnapshot,
      packageName: packageSnapshot.name,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await doc.ref.set(patch, { merge: true });
    await db.collection('offices').doc(doc.id).set(patch, { merge: true });
    updated += 1;
    console.log(`demo unlimited package officeUid=${doc.id}`);
  }

  console.log(`done updated=${updated}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
